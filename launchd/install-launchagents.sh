#!/usr/bin/env bash
# install-launchagents.sh — render jobs.yaml × plist.template into
# ~/Library/LaunchAgents and load them. Idempotent: re-running re-renders each
# plist and reloads only the ones whose content changed.
#
# Usage:
#   ./install-launchagents.sh            # render + (re)load
#   ./install-launchagents.sh --dry-run  # print what would happen, write nothing
#
# Env:
#   OPENCLAW_HOME   the .openclaw install dir for path expansion
#                   (default: $HOME/.openclaw)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS_YAML="$SCRIPT_DIR/jobs.yaml"
TEMPLATE="$SCRIPT_DIR/plist.template"
LA_DIR="$HOME/Library/LaunchAgents"
: "${OPENCLAW_HOME:=$HOME/.openclaw}"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '   %s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '   %s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '   %s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
abort(){ err "$1"; exit 1; }

[[ -f "$JOBS_YAML" ]] || abort "jobs.yaml not found: $JOBS_YAML"
[[ -f "$TEMPLATE" ]]  || abort "plist.template not found: $TEMPLATE"
command -v python3 >/dev/null 2>&1 || abort "python3 not installed"

[[ "$DRY_RUN" -eq 1 ]] && warn "DRY RUN — no files written, nothing loaded"

mkdir -p "$LA_DIR" "$OPENCLAW_HOME/logs"

# Emit, per job, a NUL-delimited record: label, then the rendered plist body.
# Python does the YAML parse + template substitution; bash handles launchctl.
RENDER_PY="$(cat <<'PY'
import sys, os, re
import yaml

jobs_path, tmpl_path = sys.argv[1], sys.argv[2]
ochome = os.environ.get("OPENCLAW_HOME", os.path.expanduser("~/.openclaw"))
tmpl = open(tmpl_path).read()
m = yaml.safe_load(open(jobs_path)) or {}

def render_args(cmd):
    lines = []
    for tok in cmd:
        tok = tok.replace("${OPENCLAW_HOME}", ochome)
        # XML-escape the few chars that matter inside <string>
        tok = (tok.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        lines.append(f"    <string>{tok}</string>")
    return "\n".join(lines)

def render_schedule(sched):
    if "interval" in sched:
        n = int(sched["interval"])
        return f"  <key>StartInterval</key>\n  <integer>{n}</integer>"
    cal = sched.get("calendar") or []
    out = ["  <key>StartCalendarInterval</key>", "  <array>"]
    for entry in cal:
        parts = []
        for k in ("Weekday", "Hour", "Minute", "Day", "Month"):
            if k in entry:
                parts.append(f"<key>{k}</key><integer>{int(entry[k])}</integer>")
        out.append("    <dict>" + "".join(parts) + "</dict>")
    out.append("  </array>")
    return "\n".join(out)

for j in (m.get("jobs") or []):
    label = j["label"]
    body = tmpl
    body = body.replace("{{PROGRAM_ARGS}}", render_args(j["command"]))
    body = body.replace("{{SCHEDULE_BLOCK}}", render_schedule(j["schedule"]))
    body = body.replace("{{LABEL}}", label)
    body = body.replace("${OPENCLAW_HOME}", ochome)
    sys.stdout.write(label + "\0" + body + "\0")
PY
)"

step "Rendering jobs from $JOBS_YAML"

rendered=0; loaded=0; reloaded=0; unchanged=0; failed=0
uid="$(id -u)"

# Read NUL-delimited (label, body) pairs.
while IFS= read -r -d '' label && IFS= read -r -d '' body; do
  rendered=$((rendered+1))
  dest="$LA_DIR/$label.plist"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    ok "would render → $dest"
    continue
  fi

  changed=1
  if [[ -f "$dest" ]] && diff -q <(printf '%s' "$body") "$dest" >/dev/null 2>&1; then
    changed=0
  fi

  if [[ "$changed" -eq 1 ]]; then
    printf '%s' "$body" > "$dest" || { err "$label: write failed"; failed=$((failed+1)); continue; }
  fi

  is_loaded=0
  launchctl list | grep -q "[[:space:]]$label$" && is_loaded=1

  if [[ "$changed" -eq 0 && "$is_loaded" -eq 1 ]]; then
    unchanged=$((unchanged+1))
    ok "$label: unchanged, already loaded"
    continue
  fi

  # (Re)load: bootout if present, then bootstrap.
  [[ "$is_loaded" -eq 1 ]] && launchctl bootout "gui/$uid/$label" 2>/dev/null || true
  if launchctl bootstrap "gui/$uid" "$dest" 2>/dev/null; then
    if [[ "$is_loaded" -eq 1 ]]; then
      reloaded=$((reloaded+1)); ok "$label: reloaded"
    else
      loaded=$((loaded+1)); ok "$label: loaded"
    fi
  else
    failed=$((failed+1)); err "$label: launchctl bootstrap failed"
  fi
done < <(OPENCLAW_HOME="$OPENCLAW_HOME" python3 -c "$RENDER_PY" "$JOBS_YAML" "$TEMPLATE")

step "Summary"
if [[ "$DRY_RUN" -eq 1 ]]; then
  ok "Would render $rendered plist(s)"
else
  ok "Rendered: $rendered   Loaded: $loaded   Reloaded: $reloaded   Unchanged: $unchanged   Failed: $failed"
fi
[[ "$failed" -eq 0 ]]
