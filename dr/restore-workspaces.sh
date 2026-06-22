#!/usr/bin/env bash
# restore-workspaces.sh — clone every component repo declared in
# workspaces.manifest.yaml.template to its target path. Idempotent: skips
# entries whose target is already a git repo.
#
# Run from a clean machine after Homebrew + git are available. This script
# does NOT install gbrain Postgres or rebuild the QMD index — those are
# restore-gbrain.sh and restore-qmd.sh, run afterwards.
#
# Set GH_ORG (your GitHub org/user) so the ${GH_ORG} placeholders in the
# manifest resolve to real clone URLs.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/workspaces.manifest.yaml.template"
: "${GH_ORG:=}"

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '   %s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '   %s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '   %s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
abort(){ err "$1"; exit 1; }

[[ -f "$MANIFEST" ]] || abort "manifest not found: $MANIFEST"
command -v git >/dev/null 2>&1 || abort "git not installed"
command -v python3 >/dev/null 2>&1 || abort "python3 not installed"

if [[ -z "$GH_ORG" ]] && grep -q '\${GH_ORG}' "$MANIFEST"; then
  abort "manifest references \${GH_ORG} but GH_ORG is unset — export GH_ORG=<your-org> first"
fi

# Parse manifest into "role|url|path" lines via python3+PyYAML.
# ${GH_ORG} and $HOME placeholders are expanded here.
ENTRIES=$(GH_ORG="$GH_ORG" python3 - "$MANIFEST" <<'PY'
import sys, os
try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML missing — run: pip3 install pyyaml\n")
    sys.exit(2)
org = os.environ.get("GH_ORG", "")
m = yaml.safe_load(open(sys.argv[1]))
for w in (m.get('workspaces') or []):
    url  = w['url'].replace('${GH_ORG}', org)
    path = os.path.expanduser(w['path'])
    print(f"{w['role']}|{url}|{path}")
PY
)

if [[ -z "$ENTRIES" ]]; then
  abort "manifest parsed empty — check workspaces: list"
fi

step "Restoring workspaces from $MANIFEST"

cloned=0; skipped=0; failed=0
while IFS='|' read -r role url path; do
  [[ -z "$role" ]] && continue

  if [[ -d "$path/.git" ]]; then
    existing=$(git -C "$path" remote get-url origin 2>/dev/null || echo "")
    if [[ "$existing" == "$url" ]]; then
      ok "$role  already cloned at $path"
      skipped=$((skipped+1))
      continue
    else
      warn "$role  exists at $path but remote mismatch (have: $existing)"
      failed=$((failed+1))
      continue
    fi
  fi

  parent=$(dirname "$path")
  mkdir -p "$parent"

  if git clone --quiet "$url" "$path"; then
    ok "$role  cloned to $path"
    cloned=$((cloned+1))
  else
    err "$role  clone failed: $url -> $path"
    failed=$((failed+1))
  fi
done <<< "$ENTRIES"

step "Summary"
ok "Cloned: $cloned   Skipped (already present): $skipped   Failed: $failed"

if [[ "$failed" -gt 0 ]]; then
  err "Some entries failed — review above"
  exit 1
fi

step "Next steps"
ok "Run restore-gbrain.sh to import the Postgres dumps from gbrain-backups"
ok "Run restore-qmd.sh to rebuild the QMD vector index"
ok "Run smoke-test.sh to verify the full stack"
