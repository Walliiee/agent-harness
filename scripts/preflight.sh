#!/usr/bin/env bash
# preflight.sh — clone-level health + dependency doctor for agent-harness.
#
# Runs on a FRESH CLONE with no live stack installed. Tells you exactly what is
# present and what is missing, split into:
#   REQUIRED  — needed for the template path (adapt.py render + apply).
#   SCHEDULER — needed only to install/verify the macOS LaunchAgents + DR tooling.
#   OPTIONAL  — the full live memory stack (Postgres/Gbrain/QMD/etc.).
#
# Exit 0 if the REQUIRED template path is satisfied (missing scheduler/optional
# tools only warn). Exit 1 if a REQUIRED dependency or repo file is missing.
#
# This is the CLONE-LEVEL check. For a check of an already-installed live system
# (services up, indices populated, workspaces cloned), use dr/smoke-test.sh after
# bootstrap.
#
# Usage: scripts/preflight.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -t 1 ]]; then
  c_grn=$'\033[32m'; c_red=$'\033[31m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_rst=$'\033[0m'
else
  c_grn=''; c_red=''; c_yel=''; c_dim=''; c_rst=''
fi

req_fail=0
section() { printf '\n%s== %s ==%s\n' "$c_dim" "$1" "$c_rst"; }
ok()      { printf '  %s✓%s %s\n' "$c_grn" "$c_rst" "$*"; }
miss_req(){ printf '  %s✗%s %s\n' "$c_red" "$c_rst" "$*"; req_fail=1; }
warn()    { printf '  %s•%s %s\n' "$c_yel" "$c_rst" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }
ver()  { "$@" 2>&1 | head -1; }

# ---------------------------------------------------------------- REQUIRED ----
section "Required — template path (adapt.py)"

# Python 3.9+
if have python3; then
  pyv=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo "?")
  if python3 -c 'import sys;sys.exit(0 if sys.version_info[:2]>=(3,9) else 1)' 2>/dev/null; then
    ok "python3 $pyv (>= 3.9)"
  else
    miss_req "python3 $pyv found, but 3.9+ is required for adapt.py"
  fi
else
  miss_req "python3 not found — required (adapt.py is pure stdlib Python 3.9+)"
fi

# git
if have git; then ok "git — $(ver git --version)"; else miss_req "git not found — required to clone/push workspaces"; fi

# Repo structure
need_files=(
  scripts/adapt.py scripts/scrub-audit.sh
  config/openclaw.json.template launchd/plist.template launchd/jobs.yaml
  dr/bootstrap.sh dr/workspaces.manifest.yaml.template
)
miss=0
for f in "${need_files[@]}"; do [[ -e "$f" ]] || { miss_req "missing repo file: $f"; miss=1; }; done
[[ "$miss" -eq 0 ]] && ok "repo structure intact (${#need_files[@]} key files present)"
[[ -d skills ]] && ok "skills/ bundle present ($(find skills -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ') skills)" || warn "skills/ directory not found"

# adapt.py functional dry-run (writes nothing; renders to a temp probe)
if have python3 && [[ -f scripts/adapt.py ]]; then
  tmp="${TMPDIR:-/tmp}/agent-harness-preflight.$$"
  if python3 scripts/adapt.py --home "$tmp" --gh-org preflight-org --agents main,dev >/dev/null 2>&1; then
    ok "adapt.py dry-run renders + validates cleanly"
  else
    miss_req "adapt.py dry-run FAILED — run it directly to see the error:
      python3 scripts/adapt.py --home /tmp/x --gh-org my-org --agents main,dev"
  fi
fi

# --------------------------------------------------------------- SCHEDULER ----
section "Scheduler + DR tooling"

# PyYAML — required by the scheduler installer, restore-*, and smoke-test (NOT adapt.py).
if have python3 && python3 -c 'import yaml' 2>/dev/null; then
  ok "PyYAML present (needed by install-launchagents.sh, restore-*, smoke-test)"
else
  warn "PyYAML missing — install with: pip3 install pyyaml
      (only needed to install/verify LaunchAgents + DR restore; adapt.py does not need it)"
fi

case "$(uname -s)" in
  Darwin) ok "macOS — LaunchAgents + dr/bootstrap.sh supported" ;;
  Linux)  warn "Linux — adapt.py + skills work; LaunchAgents + dr/bootstrap.sh are macOS-only (port the scheduler yourself)" ;;
  *)      warn "$(uname -s) — only the template path is expected to work; scheduler/DR are macOS-oriented" ;;
esac

have gh && ok "gh (GitHub CLI) — $(ver gh --version | head -1)" || warn "gh not found — optional; used to create/push the workspace repos"

# ---------------------------------------------------------------- OPTIONAL ----
section "Optional — full live memory stack"

# vge A B → true (exit 0) if dotted-numeric version A >= B. Pure awk, so it
# works on macOS bash 3.2 and Linux alike (no `sort -V`, no `declare -A`).
vge() {
  awk -v a="$1" -v b="$2" 'BEGIN{
    na=split(a,A,"."); nb=split(b,B,"."); n=(na>nb)?na:nb;
    for(i=1;i<=n;i++){x=(i<=na)?A[i]+0:0; y=(i<=nb)?B[i]+0:0;
      if(x>y)exit 0; if(x<y)exit 1}
    exit 0}'
}

# note_opt NAME DESC [VERSION_FLAG] [FLOOR] [TESTED]
# Optional tool: present → ✓ with its version; if a FLOOR is given and the tool
# is below it, add a warn-only "below tested baseline" note (never fails the run).
# FLOOR/TESTED here MUST track the "Tested with" table in README.md.
note_opt() {
  local name="$1" desc="$2" vflag="${3:---version}" floor="${4:-}" tested="${5:-}"
  if have "$name"; then
    local raw v
    raw=$(ver "$name" "$vflag" 2>/dev/null | head -1)
    v=$(printf '%s' "$raw" | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)
    ok "$name — $desc ($raw)"
    if [[ -n "$floor" && -n "$v" ]] && ! vge "$v" "$floor"; then
      warn "  ↳ $name $v is below the tested baseline $floor (known-good: $tested) — untested, update recommended"
    fi
  else
    warn "$name not found — $desc (optional; the memory skills degrade gracefully)"
  fi
}
#         tool      description                          ver-flag    floor    known-good
note_opt psql    "Postgres client (Gbrain graph store)" --version   17       17.10
note_opt bun     "Bun runtime (Gbrain install)"         --version   1.3      1.3.14
note_opt qmd     "QMD vector index"                     --version   2.5      2.5.3
note_opt gbrain  "Gbrain knowledge graph"               --version   0.42     0.42.40.0
note_opt ollama  "Ollama (embeddings / local models)"   --version   0.30     0.30.0
note_opt openclaw "OpenClaw gateway"                    --version   2026.6   2026.6.9

# ------------------------------------------------------------------ SUMMARY ---
echo
if [[ "$req_fail" -eq 0 ]]; then
  printf '%s✓ preflight: the template path is ready.%s Run the dry-run:\n' "$c_grn" "$c_rst"
  printf '    python3 scripts/adapt.py --home ~/.openclaw --gh-org my-org --agents main,dev\n'
  exit 0
else
  printf '%s✗ preflight: a REQUIRED dependency or file is missing (see ✗ above).%s\n' "$c_red" "$c_rst"
  exit 1
fi
