#!/usr/bin/env bash
# scrub-audit.sh — leak gate for the agent-harness OSS repo.
#
# Fails (exit 1) if any author-specific identifier, absolute home path, or
# secret-shaped value is found in tracked files. Run before every commit and
# in CI. This is the single check that makes "no personal data ships" enforceable.
#
# Usage: scripts/scrub-audit.sh        (scans the repo root)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Identifiers that must NEVER appear in a published file. Add as needed.
# (These are the author's real values — the whole point is they are absent.)
PATTERNS=(
  # absolute home path of the author's machine
  '${OPENCLAW_HOME}'
  # author GitHub org / handle (repo URLs should use ${GH_ORG} placeholder)
  'Walliiee'
  # author name / contact
  'REDACTED'
  # Telegram numeric IDs (owner, groups, topics)
  'REDACTED'
  'REDACTED'
  'REDACTED'
  # secret-shaped values
  'gbrain_at_[a-f0-9]'
  'REDACTED'
  '[A-Za-z0-9_-]*sk-[A-Za-z0-9]{20,}'   # OpenAI-style keys
  '[a-f0-9]{40,}'                        # long hex secrets
  # domain personas that should be generic in the OSS cut
  'REDACTED' 'REDACTED' 'REDACTED' 'REDACTED' 'REDACTED'
)

# Files/dirs exempt from the persona check live nowhere — personas must be generic
# everywhere. Only .git is excluded from the whole scan.
EXCLUDE='--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=__pycache__'

# The author GitHub handle is banned everywhere as an accidental-leak guard, with
# ONE deliberate exception: intentional author credit in the LICENSE file. It must
# still never appear anywhere else (URLs use the ${GH_ORG} placeholder).
AUTHOR_HANDLE='Walliiee'

fail=0
for pat in "${PATTERNS[@]}"; do
  # shellcheck disable=SC2086
  hits=$(grep -rInE $EXCLUDE -- "$pat" . 2>/dev/null | grep -vF 'scripts/scrub-audit.sh')
  # Allow the author handle in LICENSE only (intentional copyright credit).
  if [ "$pat" = "$AUTHOR_HANDLE" ] && [ -n "$hits" ]; then
    hits=$(printf '%s\n' "$hits" | grep -vE '^\./LICENSE:' || true)
  fi
  if [ -n "$hits" ]; then
    echo "✗ LEAK — pattern '$pat':"
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "✓ scrub-audit clean — no author identifiers, paths, or secrets in tracked files."
else
  echo
  echo "scrub-audit FAILED. Replace the above with placeholders (\${OPENCLAW_HOME}, \${GH_ORG}, env vars) before committing."
fi
exit "$fail"
