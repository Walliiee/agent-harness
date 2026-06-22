---
name: freshness-watch
version: 1.0.0
description: Weekly freshness audit — detects stale workspace artifacts (daily files not rotated, handoffs not written, skill-run records not archived) and surfaces them in the Sunday digest.
triggers:
  - check workspace freshness
  - weekly staleness audit
license: MIT
metadata: {"openclaw": {"emoji": "🌱"}}
---

# freshness-watch — weekly staleness audit

Detects workspace state that's drifted out of its expected refresh cadence. The primary signal we don't want to miss: rotation, archive, or maintenance jobs that silently stopped firing.

## When this runs

- **Primary: cron.** `ai.openclaw.freshness-watch.plist` fires Sunday 05:00.
- **Wrapper**: through `skill-wrapper --skill freshness-watch --agent main --trigger cron`.

## What it does

Invokes `${OPENCLAW_HOME}/bin/freshness-watch`:

1. Check daily files older than expected rotation window across all configured workspaces (see `${OPENCLAW_HOME}/config/agents.map`).
2. Check missing/stale handoff files.
3. Check skill-runs ledger archive freshness.
4. Report to stdout (captured in launchd log); emit Drift incident on hard violations.

## Exit codes

- `0` — clean or soft-warn only
- `non-zero` — hard violation detected

## Files

- Script: `${OPENCLAW_HOME}/bin/freshness-watch`
- Plist: `$HOME/Library/LaunchAgents/ai.openclaw.freshness-watch.plist`
- This spec: `${OPENCLAW_HOME}/skills/freshness-watch/SKILL.md`

## Related

- `daily-notes-rotate` — the rotation job freshness-watch verifies.
- `skill-run-archive` — archive job freshness-watch verifies.
