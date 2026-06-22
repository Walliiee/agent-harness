---
name: promote-queue-status
version: 1.0.0
description: Summarize promote-queue.md state across all configured workspaces in JSON, one-line human, or markdown table format. Primitive for digest surfaces (Telegram, consolidated handoff, console).
triggers:
  - promote queue status
  - what is in the promote queue
license: MIT
metadata: {"openclaw": {"emoji": "📥"}}
---

# promote-queue-status — digest primitive

The single canonical source-of-truth for "what's pending review in the promote queues across all agents." Designed to be consumed by whatever digest surface needs the data — Telegram one-liner, consolidated handoff table, console summary.

## Why this is a primitive (not a digest itself)

The Telegram digest infrastructure may be partial (incident-notify exists, but there may be no general daily-digest aggregator). Rather than build the full digest, this skill ships the primitive that the digest *will* consume when it exists. Three output modes cover the common surfaces:

| Mode | Surface | Format |
|---|---|---|
| `--json` (default) | machine consumers, future scripts | structured JSON |
| `--human` | Telegram one-liner | single line with emoji |
| `--markdown` | consolidated handoff section | `##` heading + summary + table |

## How to invoke

```bash
${OPENCLAW_HOME}/bin/promote-queue-status                # JSON
${OPENCLAW_HOME}/bin/promote-queue-status --human        # one-liner
${OPENCLAW_HOME}/bin/promote-queue-status --markdown     # table block
```

## What it counts

For each workspace's `memory/promote-queue.md`:

1. Parse the `## Queue` section (skips the format-docs prologue).
2. Match entry headers of the form `## YYYY-MM-DD — <summary> (score: <n>)`.
3. Compute age in days for each.
4. Flag entries older than 14 days as **stale** (mirrors the `stuck-queue` invariant in `memory-bloat-audit`).

## Output schema (JSON)

```json
{
  "today": "YYYY-MM-DD",
  "totals": {
    "items": int,
    "stale": int,
    "agents_with_items": int,
    "oldest_age_days": int | null
  },
  "queues": [
    {
      "workspace": "workspace",
      "agent": "main",
      "queue_items": int,
      "stale_items": int,
      "oldest_age_days": int | null,
      "entries": [
        {"date": "...", "summary": "...", "score": float|null, "age_days": int, "stale": bool}
      ]
    }
  ]
}
```

## Exit codes

- `0` — clean (any item count, including zero)
- `2` — script-level error

## When to wire into a digest

When the Telegram daily-digest skill exists, it should call `promote-queue-status --human` and embed the one-liner in its body. When the consolidated handoff generator exists, it should call `--markdown` and append the section.

Until then, this script is callable standalone (`watch -n 600 promote-queue-status --human` for a poor-person's TUI; `promote-queue-status > /tmp/today-promote-state.json` for ad-hoc analysis).

## Files

- Script: `${OPENCLAW_HOME}/bin/promote-queue-status` (Python, ~170 lines)
- This spec: `${OPENCLAW_HOME}/skills/promote-queue-status/SKILL.md`

## Related

- `memory-promote` — populates the queues this skill summarizes.
- `memory-bloat-audit` — uses the same 14-day staleness threshold via the `stuck-queue` invariant.
- `incident-notify` — Telegram sender pattern for future digest skills.
