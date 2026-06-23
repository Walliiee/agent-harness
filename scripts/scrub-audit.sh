#!/usr/bin/env bash
# scrub-audit.sh — leak gate for the agent-harness OSS repo.
#
# Fails (exit 1) if a secret-shaped value, or any author-specific identifier from
# your local denylist, is found in tracked files. Run before every commit and in
# CI. This is the single check that makes "no personal data ships" enforceable.
#
# Two tiers:
#   1. STRUCTURAL patterns (below) — generic secret SHAPES (sk- keys, long hex,
#      private-key headers). Safe to publish; they contain no real value. Always
#      checked, including in CI.
#   2. LITERAL denylist — your real identifiers (home path, handle, domain, chat
#      IDs, persona names). These must NEVER live in a tracked file, so they are
#      read from scripts/.scrub-denylist, which is gitignored. Copy
#      scripts/.scrub-denylist.example -> scripts/.scrub-denylist and fill it in.
#      Missing file => literal checks are skipped (the CI default — CI has no copy
#      of your secrets, by design; your local pre-commit run is the real guard).
#
# Usage: scripts/scrub-audit.sh        (scans the repo root)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- Tier 1: structural secret shapes (tracked, no real values) ---------------
STRUCTURAL=(
  '[A-Za-z0-9_-]*sk-[A-Za-z0-9]{20,}'        # OpenAI-style keys
  'AKIA[0-9A-Z]{16}'                          # AWS access key id
  'gbrain_at_[a-f0-9]'                        # gbrain token prefix shape
  '[a-f0-9]{40,}'                             # long hex secrets / tokens
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'        # PEM private keys
)

# --- Tier 2: author-specific literals (local, gitignored) ---------------------
# One grep -E pattern per line. Blank lines and #-comments ignored. A line may
# end with "  @allow=<grep-pattern>" to whitelist matches whose "path:line"
# location matches that pattern (e.g. an intentional credit in LICENSE).
DENYLIST_FILE="$ROOT/scripts/.scrub-denylist"
LITERALS=()        # parallel arrays: pattern + its optional allow-pattern
ALLOWS=()
if [ -f "$DENYLIST_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    allow=''
    if printf '%s' "$line" | grep -q '  @allow='; then
      allow="${line##*  @allow=}"
      line="${line%%  @allow=*}"
    fi
    LITERALS+=("$line")
    ALLOWS+=("$allow")
  done < "$DENYLIST_FILE"
else
  echo "ℹ scrub-audit: no scripts/.scrub-denylist found — checking structural"
  echo "  secret shapes only. Copy .scrub-denylist.example to enable identity"
  echo "  checks locally. (CI runs structural-only by design.)"
fi

# The local denylist must NEVER be committed — it holds your real values.
if git ls-files --error-unmatch scripts/.scrub-denylist >/dev/null 2>&1; then
  echo "✗ scripts/.scrub-denylist is tracked — it must stay gitignored."
  exit 1
fi

EXCLUDE='--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=__pycache__'
# This script and the local denylist necessarily contain the patterns; skip them.
SELF='scripts/scrub-audit.sh'
DENY='scripts/.scrub-denylist'

scan() {  # $1=pattern  $2=allow-pattern(optional)
  local pat="$1" allow="${2:-}" hits
  # shellcheck disable=SC2086
  hits=$(grep -rInE $EXCLUDE -- "$pat" . 2>/dev/null \
        | grep -vF "$SELF" | grep -vF "$DENY")
  if [ -n "$allow" ] && [ -n "$hits" ]; then
    hits=$(printf '%s\n' "$hits" | grep -vE "$allow" || true)
  fi
  printf '%s' "$hits"
}

fail=0
report() {  # $1=pattern  $2=hits
  echo "✗ LEAK — pattern '$1':"
  echo "$2" | sed 's/^/    /'
  fail=1
}

for pat in "${STRUCTURAL[@]}"; do
  hits=$(scan "$pat"); [ -n "$hits" ] && report "$pat" "$hits"
done
for i in "${!LITERALS[@]}"; do
  hits=$(scan "${LITERALS[$i]}" "${ALLOWS[$i]}")
  [ -n "$hits" ] && report "${LITERALS[$i]}" "$hits"
done

if [ "$fail" -eq 0 ]; then
  echo "✓ scrub-audit clean — no secret shapes or denylisted identifiers in tracked files."
else
  echo
  echo "scrub-audit FAILED. Replace the above with placeholders (\${OPENCLAW_HOME}, \${GH_ORG}, env vars) before committing."
fi
exit "$fail"
