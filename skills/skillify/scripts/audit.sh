#!/usr/bin/env bash
# Usage: audit.sh <skill-dir>
# Runs measure + validate-frontmatter and prints a combined pre-audit summary.
# Use this before the manual checklist to ground the audit in hard numbers.
set -uo pipefail

SKILL_DIR="${1:?Usage: audit.sh <skill-dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Pre-audit: $(basename "$SKILL_DIR") ==="
echo ""

echo "--- Measurements ---"
"$SCRIPT_DIR/measure.sh" "$SKILL_DIR" || true
echo ""

echo "--- Frontmatter ---"
"$SCRIPT_DIR/validate-frontmatter.sh" "$SKILL_DIR" || true
echo ""

if command -v skills-ref &>/dev/null; then
  echo "--- skills-ref validate ---"
  skills-ref validate "$SKILL_DIR" || true
  echo ""
else
  echo "INFO  skills-ref not found — skipping spec validator (install for full coverage)"
  echo ""
fi

echo "=== Done. Review findings above before running the full checklist. ==="
