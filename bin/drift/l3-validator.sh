#!/usr/bin/env bash
# L3 Validator — Drift pipeline claim cross-checker.
#
# Reads a composed message from stdin or --message, extracts claims via regex,
# verifies each claim against its ground-truth source, and blocks sends that
# contain fabricated claims.
#
# Truth sources:
#   - Application claims  -> $L3_APPLICATIONS_FILE (a tracker markdown file; optional)
#   - Streak claims       -> ~/.openclaw/heartbeat-state/*.json (count fields)
#   - Cron claims         -> `openclaw cron list`
#   - gbrain claims       -> http://localhost:8182 (best-effort, soft-fail)
#
# Exit codes:
#   0  all claims verified (or no claims found)
#   1  fabrication detected
#   2  validator error (bad input, missing dependency)
#
# Usage:
#   echo "Streak: 7. Submitted to Novo Nordisk." | l3-validator.sh
#   l3-validator.sh --message "..." --cron-name "Daily Ops Digest" --agent main --emit-incident
#
# Integration (cron pipeline wiring):
#
#   In a session-cleanup cron skill, after the LLM composes the handoff/digest
#   message but BEFORE invoking `message.send` (or the announce/Telegram step):
#
#     1. Capture the composed message to $COMPOSED (a file or shell var).
#     2. Run:
#          verdict=$(printf '%s' "$COMPOSED" | \
#              ~/.openclaw/bin/drift/l3-validator.sh \
#                --cron-name "<this-cron-name>" \
#                --agent "<this-agent>" \
#                --emit-incident)
#          rc=$?
#     3. If $rc == 0  -> proceed with message.send as normal.
#        If $rc == 1  -> ABORT the send. The validator has already filed a
#                        Drift incident under ~/.openclaw/incidents/. Either:
#                          a) silently swallow (digest is just skipped this run), or
#                          b) replace the outgoing message with a minimal
#                             "L3 blocked send — see Drift incident <id>" stub.
#        If $rc == 2  -> validator error. Log to the cron's stderr and proceed
#                        (do not block on validator infrastructure faults).
#
#   Typical crons in scope are message-composing families, e.g.:
#     - "Session cleanup — <agent>"
#     - "Daily Ops Digest — <agent>"
#
#   These all compose a message and then call message.send/announce; the
#   validator slot is the line right before that call.

set -uo pipefail

# --- config ---------------------------------------------------------------

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
# Application-claim truth source: an optional tracker markdown file. No default
# workspace is assumed — set L3_APPLICATIONS_FILE to enable application checks.
APPLICATIONS_FILE="${L3_APPLICATIONS_FILE:-$OPENCLAW_HOME/workspace/APPLICATIONS.md}"
HEARTBEAT_DIR="${L3_HEARTBEAT_DIR:-$OPENCLAW_HOME/heartbeat-state}"
GBRAIN_URL="${L3_GBRAIN_URL:-http://localhost:8182}"
INCIDENT_CLI="${L3_INCIDENT_CLI:-$OPENCLAW_HOME/bin/incident}"
OPENCLAW_CLI="${L3_OPENCLAW_CLI:-openclaw}"

MESSAGE=""
CRON_NAME=""
AGENT=""
EMIT_INCIDENT=0
QUIET=0

# --- args -----------------------------------------------------------------

usage() {
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --message)      MESSAGE="$2"; shift 2 ;;
        --cron-name)    CRON_NAME="$2"; shift 2 ;;
        --agent)        AGENT="$2"; shift 2 ;;
        --emit-incident) EMIT_INCIDENT=1; shift ;;
        --quiet)        QUIET=1; shift ;;
        -h|--help)      usage ;;
        *)              echo "unknown arg: $1" >&2; usage ;;
    esac
done

if [ -z "$MESSAGE" ]; then
    if [ -t 0 ]; then
        echo "error: no message provided (use --message or pipe to stdin)" >&2
        exit 2
    fi
    MESSAGE="$(cat)"
fi

if [ -z "$MESSAGE" ]; then
    # empty message — nothing to validate
    printf '{"passed":true,"claims_checked":0,"failures":[]}\n'
    exit 0
fi

# --- failure accumulator (JSON array, built as a string) ------------------

FAILURES_JSON=""
CLAIMS_CHECKED=0

add_failure() {
    # $1 type, $2 claim text, $3 reason
    local t="$1" c="$2" r="$3"
    local entry
    entry=$(jq -nc --arg type "$t" --arg claim "$c" --arg reason "$r" \
        '{type:$type,claim:$claim,reason:$reason}')
    if [ -z "$FAILURES_JSON" ]; then
        FAILURES_JSON="$entry"
    else
        FAILURES_JSON="$FAILURES_JSON,$entry"
    fi
}

bump_checked() { CLAIMS_CHECKED=$((CLAIMS_CHECKED + 1)); }

# --- helpers --------------------------------------------------------------

# Lowercase a string (portable).
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Iterate regex matches in MESSAGE. Prints each capture group 1 on its own line.
# Uses grep -oP if available, else falls back to sed-driven loop.
matches() {
    local pattern="$1"
    if grep -oPi "$pattern" <<< "$MESSAGE" 2>/dev/null; then
        return 0
    fi
    return 0
}

# --- 1. Streak claims -----------------------------------------------------
# Patterns: "streak: N", "N-day streak", "streak of N", "streak is N"
# Truth source: any *.json under heartbeat-state/ with a "count" field.
# A claim is verified if SOME heartbeat counter equals N, or N==0 and no
# counters exist. A claim is rejected if no counter matches.

check_streaks() {
    # Pull all candidate N values from the message.
    local nums
    nums=$(printf '%s\n' "$MESSAGE" | grep -oEi \
        '(streak[[:space:]]*(of|is|:|=)?[[:space:]]*[0-9]+|[0-9]+[[:space:]]*[- ]?day[[:space:]]*streak)' \
        | grep -oE '[0-9]+' | sort -u)

    [ -z "$nums" ] && return 0

    # Gather all "count" values from heartbeat state files.
    local known_counts=""
    if [ -d "$HEARTBEAT_DIR" ]; then
        known_counts=$(find "$HEARTBEAT_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null \
            | while read -r f; do
                jq -r '.. | objects | .count? // empty' "$f" 2>/dev/null
            done | sort -u)
    fi

    local n
    for n in $nums; do
        bump_checked
        local claim="streak: $n"
        # Zero-streak claims are vacuous: absence of a counter == 0, so accept.
        [ "$n" = "0" ] && continue
        if [ -z "$known_counts" ]; then
            add_failure "streak" "$claim" \
                "no counter files contain a 'count' field; cannot substantiate streak=$n"
            continue
        fi
        if ! grep -qxF "$n" <<< "$known_counts"; then
            add_failure "streak" "$claim" \
                "no heartbeat-state counter has count=$n (known: $(echo "$known_counts" | paste -sd, -))"
        fi
    done
}

# --- 2. Application claims ------------------------------------------------
# Patterns: "submitted to <Company>", "applied to <Company>",
#           "application to <Company>"
# Truth source: APPLICATIONS.md — company must appear on a "📨 Submitted" line.
# Company name capture is greedy-bounded to stop at sentence punctuation.

check_applications() {
    [ -f "$APPLICATIONS_FILE" ] || {
        # No truth source available; if claims exist, that's a fabrication risk.
        # But missing source is a config issue — soft-fail with a warning claim.
        if printf '%s' "$MESSAGE" | grep -qiE '(submitted|applied|application) to [A-Z]'; then
            bump_checked
            add_failure "application" "<applications-source-missing>" \
                "APPLICATIONS.md not found at $APPLICATIONS_FILE; cannot verify application claims"
        fi
        return 0
    }

    # Extract company names after the trigger phrases. Case-sensitive on the
    # company tokens (so we stop at the first lowercase word), case-insensitive
    # on the trigger via explicit alternation.
    local extracted
    extracted=$(printf '%s\n' "$MESSAGE" | grep -oE \
        '([Ss]ubmitted|SUBMITTED|[Aa]pplied|APPLIED|[Aa]pplication|APPLICATION)[[:space:]]+([Tt]o|TO|[Aa]t|AT)[[:space:]]+[A-Z][A-Za-z0-9&_/-]+([[:space:]]+[A-Z][A-Za-z0-9&_/-]+){0,3}' \
        | sed -E 's/^[[:alpha:]]+[[:space:]]+[[:alpha:]]+[[:space:]]+//')

    [ -z "$extracted" ] && return 0

    # Fabrication test = "is this company in APPLICATIONS.md at all?".
    # We don't try to distinguish Submitted vs. R1 vs. Rejected — the company's
    # mere presence in the tracker means the operator has acted on it. Stage
    # drift is a different error class and not L3's job.
    local applications_blob
    applications_blob=$(cat "$APPLICATIONS_FILE" 2>/dev/null || true)

    while IFS= read -r company; do
        [ -z "$company" ] && continue
        company=$(printf '%s' "$company" | sed -E 's/[[:space:].,;:!?]+$//')
        [ -z "$company" ] && continue
        bump_checked
        if ! printf '%s' "$applications_blob" | grep -qiF "$company"; then
            add_failure "application" "submitted to $company" \
                "no entry in APPLICATIONS.md mentions '$company'"
        fi
    done <<< "$(printf '%s\n' "$extracted" | sort -u)"
}

# --- 3. Cron claims -------------------------------------------------------
# Patterns: "cron <name> in error", "cron <name> failed", "<name> cron failed",
#           "cron <name> errored", "cron <name> is broken"
# Truth source: `openclaw cron list` Status column.

check_crons() {
    # Quick scan for trigger keywords before invoking openclaw.
    if ! printf '%s' "$MESSAGE" | grep -qiE 'cron[^[:alnum:]]+.*(error|fail|broken|down|red)'; then
        return 0
    fi

    if ! command -v "$OPENCLAW_CLI" >/dev/null 2>&1; then
        bump_checked
        add_failure "cron" "<cron-cli-missing>" \
            "$OPENCLAW_CLI not on PATH; cannot verify cron-status claims"
        return 0
    fi

    local cron_list
    cron_list=$("$OPENCLAW_CLI" cron list 2>/dev/null) || {
        bump_checked
        add_failure "cron" "<cron-list-failed>" \
            "'openclaw cron list' exited non-zero; cannot verify cron-status claims"
        return 0
    }

    # Extract claimed cron identifiers. Two pattern shapes:
    #   "cron <Word(s)> (error|failed|broken|...)"
    #   "<Word(s)> cron (error|failed|broken|...)"
    # Keep capture lightweight: 1-5 tokens.
    local claimed
    claimed=$(printf '%s\n' "$MESSAGE" | grep -oEi \
        'cron[[:space:]]+[A-Za-z0-9][A-Za-z0-9 _.-]{1,60}?[[:space:]]+(in[[:space:]]+error|errored|failed|is[[:space:]]+broken|broken|down|red)' \
        | sed -E 's/^cron[[:space:]]+//I; s/[[:space:]]+(in[[:space:]]+error|errored|failed|is[[:space:]]+broken|broken|down|red)$//I' \
        | sort -u)

    [ -z "$claimed" ] && return 0

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        bump_checked
        # Look up the cron by substring; check its Status column.
        local row status
        row=$(printf '%s\n' "$cron_list" | grep -iF -- "$name" | head -1)
        if [ -z "$row" ]; then
            add_failure "cron" "cron $name (claimed broken)" \
                "no cron in 'openclaw cron list' matches name '$name'"
            continue
        fi
        # Status is the 6th column in the listing. Use awk on the row.
        # The list is whitespace-aligned, so awk works on column count: ID, Name (may have spaces, truncated with …), Schedule (multi-word), Next, Last, Status, ...
        # Heuristic: status is the token "ok" or "error" appearing in the row.
        if printf '%s' "$row" | grep -qE '[[:space:]]error[[:space:]]'; then
            : # claim verified, cron really is in error
        elif printf '%s' "$row" | grep -qE '[[:space:]]ok[[:space:]]'; then
            add_failure "cron" "cron $name claimed broken" \
                "'openclaw cron list' shows status=ok for matching row"
        else
            # Indeterminate — don't penalize.
            :
        fi
    done <<< "$claimed"
}

# --- 4. gbrain claims -----------------------------------------------------
# Patterns: "gbrain shows X", "per gbrain X", "gbrain says X"
# Truth source: gbrain HTTP at $GBRAIN_URL. Soft-fail when gbrain is unreachable
# (we don't want a downed gbrain to block all sends — but we DO want to flag
# unverifiable claims so the operator knows).

check_gbrain() {
    local triggers
    triggers=$(printf '%s\n' "$MESSAGE" | grep -oEi \
        '(gbrain[[:space:]]+(shows|says|reports|indicates)|per[[:space:]]+gbrain)[^.\n]{1,160}' \
        | sort -u)

    [ -z "$triggers" ] && return 0

    # Probe gbrain reachability once.
    local probe
    probe=$(curl -fsS --max-time 2 "$GBRAIN_URL" 2>/dev/null; echo "::rc=$?")
    local rc=${probe##*::rc=}
    if [ "$rc" != "0" ]; then
        # Unreachable — record one summary failure regardless of trigger count
        # (don't spam, but DO flag).
        bump_checked
        add_failure "gbrain" "<gbrain-unreachable>" \
            "gbrain at $GBRAIN_URL not reachable; gbrain-sourced claims cannot be verified"
        return 0
    fi

    # Reachable but we don't have a generic verification endpoint — for each
    # trigger, attempt a /search query and require at least one hit.
    while IFS= read -r claim; do
        [ -z "$claim" ] && continue
        bump_checked
        # Use the tail of the claim (after the trigger phrase) as the query.
        local q
        q=$(printf '%s' "$claim" | sed -E 's/^(gbrain[[:space:]]+(shows|says|reports|indicates)|per[[:space:]]+gbrain)[[:space:]]+//I')
        local resp
        resp=$(curl -fsS --max-time 3 --get "$GBRAIN_URL/search" \
            --data-urlencode "q=$q" --data-urlencode "limit=1" 2>/dev/null)
        if [ -z "$resp" ]; then
            add_failure "gbrain" "$claim" \
                "gbrain /search returned no response for query: $q"
            continue
        fi
        # Accept any non-empty results array.
        local hits
        hits=$(printf '%s' "$resp" | jq -r '(.results // .hits // .data // []) | length' 2>/dev/null)
        if [ -z "$hits" ] || [ "$hits" = "0" ] || [ "$hits" = "null" ]; then
            add_failure "gbrain" "$claim" \
                "gbrain /search returned 0 hits for: $q"
        fi
    done <<< "$triggers"
}

# --- dependency check -----------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 2
fi

# --- run checks -----------------------------------------------------------

check_streaks
check_applications
check_crons
check_gbrain

# --- assemble verdict -----------------------------------------------------

PASSED="true"
EXIT=0
if [ -n "$FAILURES_JSON" ]; then
    PASSED="false"
    EXIT=1
fi

VERDICT=$(jq -nc \
    --argjson passed "$PASSED" \
    --argjson n "$CLAIMS_CHECKED" \
    --argjson failures "[${FAILURES_JSON}]" \
    '{passed:$passed, claims_checked:$n, failures:$failures}')

[ "$QUIET" -eq 0 ] && printf '%s\n' "$VERDICT"

# --- on failure, optionally emit a Drift incident -------------------------

if [ "$EXIT" -ne 0 ] && [ "$EMIT_INCIDENT" -eq 1 ]; then
    if [ ! -x "$INCIDENT_CLI" ]; then
        echo "warn: $INCIDENT_CLI not executable; skipping incident emit" >&2
    else
        TITLE="Fabricated claim in ${CRON_NAME:-<unknown-cron>}"
        # Dedup key: cron + first failure type (stable across re-runs same minute).
        FIRST_TYPE=$(printf '%s' "$VERDICT" | jq -r '.failures[0].type // "unknown"')
        DEDUP_KEY="l3-${CRON_NAME:-unknown}-${FIRST_TYPE}"
        RAW_TMP=$(mktemp -t l3-validator.XXXXXX)
        {
            printf '## Message\n\n```\n%s\n```\n\n## Verdict\n\n```json\n%s\n```\n' \
                "$MESSAGE" "$VERDICT"
        } > "$RAW_TMP"

        "$INCIDENT_CLI" emit \
            --source l3-validator \
            --type output-fabrication-watch \
            --severity high \
            --title "$TITLE" \
            ${AGENT:+--agent "$AGENT"} \
            --key "$DEDUP_KEY" \
            --fields-json "$VERDICT" \
            --raw-file "$RAW_TMP" \
            >/dev/null 2>&1 || echo "warn: incident emit failed" >&2

        rm -f "$RAW_TMP"
    fi
fi

exit "$EXIT"
