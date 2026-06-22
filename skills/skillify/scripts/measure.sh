#!/usr/bin/env bash
# Usage: measure.sh <skill-dir>
# Reports description char count and SKILL.md line count, flags violations.
set -euo pipefail

SKILL_DIR="${1:?Usage: measure.sh <skill-dir>}"
SKILL_FILE="$SKILL_DIR/SKILL.md"

if [[ ! -f "$SKILL_FILE" ]]; then
  echo "ERROR: SKILL.md not found at $SKILL_FILE" >&2
  exit 1
fi

# Extract description — handles plain strings and block scalars (>-, |-)
description=$(awk '
  /^---/ { fences++; next }
  fences == 1 && /^description:/ {
    sub(/^description:[[:space:]]*/, "")
    if ($0 ~ /^[>|]-?$/) { block=1; next }
    gsub(/^"|"$/, ""); print; exit
  }
  fences == 1 && block && /^  / { sub(/^  /, ""); line=$0; gsub(/^"|"$/, "", line); printf "%s ", line; next }
  fences == 1 && block && !/^  / { print ""; exit }
  fences == 2 { exit }
' "$SKILL_FILE" | sed 's/[[:space:]]*$//')

if [[ -z "$description" ]]; then
  echo "ERROR: No description found in frontmatter" >&2
  exit 1
fi

desc_len=${#description}
line_count=$(wc -l < "$SKILL_FILE")

echo "Skill:        $(basename "$SKILL_DIR")"
echo "Description:  $desc_len chars"
echo "SKILL.md:     $line_count lines"
echo ""

status=0

if (( desc_len > 250 )); then
  echo "FAIL  Description over 250 chars ($desc_len) — trim to under 200"
  status=1
elif (( desc_len > 200 )); then
  echo "WARN  Description over target of 200 chars ($desc_len)"
else
  echo "PASS  Description length OK ($desc_len chars)"
fi

if (( line_count > 500 )); then
  echo "FAIL  SKILL.md over 500 lines ($line_count) — move content to references/"
  status=1
elif (( line_count > 400 )); then
  echo "WARN  SKILL.md approaching limit ($line_count/500 lines)"
else
  echo "PASS  SKILL.md line count OK ($line_count lines)"
fi

exit $status
