#!/usr/bin/env bash
# Usage: validate-frontmatter.sh <skill-dir>
# Checks required and optional frontmatter fields against the AgentSkills spec.
set -euo pipefail

SKILL_DIR="${1:?Usage: validate-frontmatter.sh <skill-dir>}"
SKILL_FILE="$SKILL_DIR/SKILL.md"
FOLDER_NAME="$(basename "$SKILL_DIR")"

if [[ ! -f "$SKILL_FILE" ]]; then
  echo "ERROR: SKILL.md not found at $SKILL_FILE" >&2
  exit 1
fi

status=0

# Extract the frontmatter block (between first and second ---)
frontmatter=$(awk '/^---/{f++; next} f==1{print} f==2{exit}' "$SKILL_FILE")

get_field() {
  local val
  val=$(echo "$frontmatter" | grep -E "^${1}:" | head -1 | sed "s/^${1}:[[:space:]]*//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  # Handle YAML block scalars (>-, |-, >, |) — read indented continuation lines
  if [[ "$val" =~ ^[\>\|] ]]; then
    val=$(echo "$frontmatter" | awk -v field="${1}:" '
      $0 ~ "^"field { found=1; next }
      found && /^  / { sub(/^  /, ""); printf "%s ", $0; next }
      found { exit }
    ' | sed 's/[[:space:]]*$//')
  fi
  echo "$val" | tr -d '"'
}

name=$(get_field "name")
description=$(get_field "description")

# --- name (required) ---
if [[ -z "$name" ]]; then
  echo "FAIL  Missing required field: name"
  status=1
else
  if [[ "$name" != "$FOLDER_NAME" ]]; then
    echo "FAIL  name '$name' does not match folder '$FOLDER_NAME'"
    status=1
  else
    echo "PASS  name: $name"
  fi

  if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [[ "$name" =~ -- ]]; then
    echo "FAIL  name '$name' invalid — must be lowercase a-z/0-9/hyphens, no leading/trailing/consecutive hyphens"
    status=1
  fi

  if (( ${#name} > 64 )); then
    echo "FAIL  name too long (${#name} chars, max 64)"
    status=1
  fi

  # Reserved words (Anthropic API surface only — not base agentskills.io spec)
  if [[ "$name" =~ anthropic|claude ]]; then
    echo "WARN  name contains reserved word — 'anthropic'/'claude' forbidden on Anthropic API surface"
  fi

  # XML tags (Anthropic API surface only)
  if [[ "$name" =~ \< ]]; then
    echo "WARN  name contains XML tag characters — forbidden on Anthropic API surface"
  fi
fi

# --- description (required) ---
if [[ -z "$description" ]]; then
  echo "FAIL  Missing required field: description"
  status=1
else
  desc_len=${#description}
  if (( desc_len > 250 )); then
    echo "WARN  description over 250 chars ($desc_len) — see Section 1 for trim guidance"
  else
    echo "PASS  description present ($desc_len chars)"
  fi

  # XML tags (Anthropic API surface only)
  if [[ "$description" =~ \< ]]; then
    echo "WARN  description contains XML tags — forbidden on Anthropic API surface"
  fi
fi

# --- metadata format (OpenClaw requires single-line JSON) ---
metadata_line=$(echo "$frontmatter" | grep -E "^metadata:" | head -1)
if [[ -n "$metadata_line" ]]; then
  metadata_val=$(echo "$metadata_line" | sed "s/^metadata:[[:space:]]*//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ ! "$metadata_val" =~ ^\{ ]]; then
    echo "WARN  metadata is not single-line JSON — OpenClaw requires: {\"openclaw\": {...}}"
  elif echo "$metadata_val" | grep -q '"openclaw"'; then
    echo "PASS  metadata.openclaw: single-line JSON"
  else
    echo "WARN  metadata present but no openclaw key — consider adding requires gating"
  fi
else
  echo "WARN  metadata.openclaw not found — consider adding emoji and requires gating"
fi

exit $status
