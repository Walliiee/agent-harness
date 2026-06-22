#!/usr/bin/env bash
# smoke-test.sh — post-restore health check.
#
# Exits non-zero if any check fails. Designed to be run after bootstrap.sh +
# restore-gbrain.sh + restore-qmd.sh on a fresh machine, but also useful as a
# day-to-day health probe.
#
# Set GH_ORG so the manifest's ${GH_ORG} placeholders resolve when checking
# workspace remotes.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/workspaces.manifest.yaml.template"
: "${GH_ORG:=}"

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
PASS=0; FAIL=0; WARN=0
pass() { printf '   %s✓%s %s\n' "$c_green" "$c_reset" "$*"; PASS=$((PASS+1)); }
fail() { printf '   %s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; FAIL=$((FAIL+1)); }
warn() { printf '   %s!%s %s\n' "$c_yellow" "$c_reset" "$*"; WARN=$((WARN+1)); }
section() { printf '\n%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }

# ----- 1. openclaw config: every ${VAR} reference resolves to a real env value -----
# It's legitimate for openclaw.json to contain `${VAR}` inside headers (e.g.
# `Authorization: Bearer ${GBRAIN_TOKEN_MAIN}`) — openclaw substitutes at
# request time from the env block. The real failure mode is a `${VAR}` that
# has no corresponding non-placeholder value in env.
section "openclaw.json placeholders resolve"
LIVE_CONFIG="$HOME/.openclaw/openclaw.json"
if [[ ! -f "$LIVE_CONFIG" ]]; then
  fail "$LIVE_CONFIG missing"
else
  ph_result=$(python3 - "$LIVE_CONFIG" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
PAT = re.compile(r'\$\{([A-Z_][A-Z0-9_]*)\}')
referenced = set()
def walk(o):
    if isinstance(o, dict):
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
    elif isinstance(o, str):
        for m in PAT.finditer(o): referenced.add(m.group(1))
walk(d)
env = d.get('env', {}) or {}
unresolved = []
for var in sorted(referenced):
    v = env.get(var, '')
    if not v or v.startswith('${'):
        unresolved.append(var)
print(",".join(unresolved))
PY
)
  if [[ -z "$ph_result" ]]; then
    pass "all \${VAR} refs resolve via env"
  else
    fail "unresolved: $ph_result"
  fi
fi

# ----- 2. QMD service health -----
section "QMD service (:8181)"
qmd_resp=$(curl -sf --max-time 3 http://localhost:8181/health 2>/dev/null || echo "")
if [[ -n "$qmd_resp" ]] && echo "$qmd_resp" | grep -q '"status":"ok"'; then
  pass "QMD healthy — $qmd_resp"
else
  fail "QMD :8181 not responding ok"
fi

# ----- 3. gbrain service health -----
section "gbrain service (:8182)"
gbrain_resp=$(curl -sf --max-time 3 http://localhost:8182/health 2>/dev/null || echo "")
if [[ -n "$gbrain_resp" ]] && echo "$gbrain_resp" | grep -q '"status":"ok"'; then
  pass "gbrain healthy — $gbrain_resp"
else
  fail "gbrain :8182 not responding ok"
fi

# ----- 4. gbrain database has real data -----
section "gbrain postgres data"
PG_PREFIXES=(/opt/homebrew/opt/postgresql@17 /usr/local/opt/postgresql@17)
PG_BIN=""
for p in "${PG_PREFIXES[@]}"; do
  [[ -x "$p/bin/psql" ]] && PG_BIN="$p/bin" && break
done
if [[ -z "$PG_BIN" ]]; then
  fail "postgresql@17 not installed"
else
  export PATH="$PG_BIN:$PATH"
  table_count=$(psql -tA -d gbrain -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' ')
  table_count="${table_count:-0}"
  if [[ "$table_count" -ge 30 ]]; then
    pages=$(psql -tA -d gbrain -c "SELECT count(*) FROM pages;" 2>/dev/null | tr -d ' ')
    chunks=$(psql -tA -d gbrain -c "SELECT count(*) FROM content_chunks;" 2>/dev/null | tr -d ' ')
    pass "$table_count tables; pages=$pages chunks=$chunks"
  else
    fail "only $table_count tables in gbrain DB (expected >=30) — restore may have failed"
  fi
fi

# ----- 5. QMD index document count -----
section "QMD index population"
export XDG_CONFIG_HOME="$HOME/.openclaw/agents/main/qmd/xdg-config"
export XDG_CACHE_HOME="$HOME/.openclaw/agents/main/qmd/xdg-cache"
docs=$(command qmd status 2>/dev/null | awk '/Total:/{print $2; exit}')
vecs=$(command qmd status 2>/dev/null | awk '/Vectors:/{print $2; exit}')
docs="${docs:-0}"; vecs="${vecs:-0}"
if [[ "$docs" -gt 100 && "$vecs" -gt 100 ]]; then
  pass "QMD: $docs docs / $vecs vectors"
else
  fail "QMD index sparse: $docs docs / $vecs vectors (expected >100 each)"
fi

# ----- 6. LaunchAgents loaded -----
section "LaunchAgents loaded"
LA_DIR="$HOME/Library/LaunchAgents"
# Derive expected labels from launchd/jobs.yaml if present; else skip.
JOBS_YAML="$SCRIPT_DIR/../launchd/jobs.yaml"
if [[ -f "$JOBS_YAML" ]] && command -v python3 >/dev/null 2>&1; then
  labels=$(python3 - "$JOBS_YAML" <<'PY'
import sys, yaml
m = yaml.safe_load(open(sys.argv[1]))
for j in (m.get('jobs') or []):
    print(j['label'])
PY
)
  total=0; loaded=0; unloaded=()
  while read -r label; do
    [[ -z "$label" ]] && continue
    total=$((total+1))
    if launchctl list | grep -q "[[:space:]]$label$"; then
      loaded=$((loaded+1))
    else
      unloaded+=("$label")
    fi
  done <<< "$labels"
  if [[ "$total" -eq 0 ]]; then
    warn "no jobs declared in jobs.yaml"
  elif [[ "$loaded" -eq "$total" ]]; then
    pass "all $loaded/$total LaunchAgents loaded"
  elif [[ "$loaded" -ge $((total * 80 / 100)) ]]; then
    warn "$loaded/$total LaunchAgents loaded; missing: ${unloaded[*]:0:5}"
  else
    fail "only $loaded/$total LaunchAgents loaded"
  fi
else
  warn "launchd/jobs.yaml not found — skipping LaunchAgent check"
fi

# ----- 7. Workspaces cloned at HEAD -----
section "Workspaces present and clean"
while IFS='|' read -r role url path; do
  [[ -z "$role" ]] && continue
  if [[ ! -d "$path/.git" ]]; then
    fail "$role: $path not a git repo"
    continue
  fi
  dirty=$(cd "$path" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(cd "$path" && git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  if [[ "$dirty" -eq 0 && "$ahead" -eq 0 ]]; then
    pass "$role: clean"
  else
    warn "$role: $dirty dirty files, $ahead commits ahead"
  fi
done < <(GH_ORG="$GH_ORG" python3 - "$MANIFEST" <<'PY'
import sys, os
import yaml
org = os.environ.get("GH_ORG", "")
m = yaml.safe_load(open(sys.argv[1]))
for w in (m.get('workspaces') or []):
    url  = w['url'].replace('${GH_ORG}', org)
    path = os.path.expanduser(w['path'])
    print(f"{w['role']}|{url}|{path}")
PY
)

# ----- 8. openclaw doctor -----
section "openclaw doctor"
if openclaw doctor >/dev/null 2>&1; then
  pass "openclaw doctor exit 0"
else
  warn "openclaw doctor non-zero — run 'openclaw doctor --fix' to inspect"
fi

# ----- summary -----
section "Summary"
printf '   %sPASS%s=%d  %sFAIL%s=%d  %sWARN%s=%d\n' \
  "$c_green" "$c_reset" "$PASS" \
  "$c_red" "$c_reset" "$FAIL" \
  "$c_yellow" "$c_reset" "$WARN"
[[ "$FAIL" -eq 0 ]]
