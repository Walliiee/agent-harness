#!/usr/bin/env bash
# restore-qmd.sh — rebuild the QMD vector index from already-cloned workspaces.
#
# QMD is a derived index: every collection points at a directory on disk
# already in git. So once bootstrap.sh has cloned the workspaces, this script
# just re-runs `qmd update` (to populate the BM25 index from the markdown files)
# and `qmd embed` (to generate the vector embeddings).
#
# First run downloads ~2.7 GB of GGUF model weights to the QMD cache dir.
# Subsequent runs are incremental.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Match the alias in ~/.zshrc — must point at OpenClaw's QMD dirs, not the
# default ones, or we'll build an empty index in the wrong place.
export XDG_CONFIG_HOME="$HOME/.openclaw/agents/main/qmd/xdg-config"
export XDG_CACHE_HOME="$HOME/.openclaw/agents/main/qmd/xdg-cache"
QMD_INDEX_DIR="$XDG_CONFIG_HOME/qmd"
QMD_CACHE_DIR="$XDG_CACHE_HOME/qmd"

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '   %s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '   %s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '   %s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
abort(){ err "$1"; exit 1; }

# ----- prereqs -----
step "Prereqs"
command -v qmd >/dev/null 2>&1 || abort "qmd not installed — run bootstrap.sh first"
ok "qmd: $(command qmd --version 2>/dev/null || echo unknown)"
command -v python3 >/dev/null 2>&1 || abort "python3 not installed"
python3 -c 'import yaml' 2>/dev/null || abort "PyYAML required to read index.yml — install: pip3 install pyyaml"

# ----- ensure XDG dirs + index.yml -----
step "Ensure QMD config in place"
mkdir -p "$QMD_INDEX_DIR" "$QMD_CACHE_DIR"
if [[ ! -f "$QMD_INDEX_DIR/index.yml" ]]; then
  cp "$SCRIPT_DIR/qmd/index.yml" "$QMD_INDEX_DIR/index.yml"
  ok "Installed qmd/index.yml from bootstrap bundle"
else
  ok "qmd/index.yml already in place"
fi

# ----- verify all collection paths exist -----
step "Verify collection source paths exist"
missing=$(python3 - "$QMD_INDEX_DIR/index.yml" <<'PY'
import sys, yaml, os
m = yaml.safe_load(open(sys.argv[1]))
miss = []
for name, c in (m.get('collections') or {}).items():
    p = os.path.expanduser(c['path'])
    if not os.path.isdir(p):
        miss.append(f"{name} -> {p}")
print("\n".join(miss))
PY
)
if [[ -n "$missing" ]]; then
  err "Some QMD collection paths are missing:"
  printf '%s\n' "$missing" | sed 's/^/     /' >&2
  err "Run bootstrap.sh to clone the workspaces first."
  exit 1
fi
ok "All collection source paths present"

# ----- update (BM25 re-index) -----
step "qmd update — re-index markdown content"
if ! command qmd update; then
  abort "qmd update failed"
fi
ok "BM25 index populated"

# ----- embed (vector index) -----
step "qmd embed — generate vector embeddings"
warn "First run downloads ~2.7 GB of GGUF models to $QMD_CACHE_DIR/models/"
warn "This can take 20-40 minutes on first run; subsequent runs are incremental."
if ! command qmd embed; then
  abort "qmd embed failed — see error above (often model download or disk space)"
fi
ok "Vector index built"

# ----- verify -----
step "Verify"
command qmd status | head -20

# Sanity check: total document count and vector count
DOCS=$(command qmd status 2>/dev/null | awk '/Total:/{print $2; exit}')
VECS=$(command qmd status 2>/dev/null | awk '/Vectors:/{print $2; exit}')
if [[ -n "$DOCS" && -n "$VECS" ]]; then
  ok "$DOCS documents indexed, $VECS vectors embedded"
  if [[ "$DOCS" -eq 0 ]]; then
    err "Zero documents indexed — something is wrong with the collection paths"
    exit 1
  fi
fi

step "Done"
ok "QMD index restored"
ok "Next: run smoke-test.sh to verify the whole stack"
