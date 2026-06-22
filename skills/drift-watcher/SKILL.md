---
name: drift-watcher
version: 1.0.0
description: Hourly cron-postmortem sweep — scans launchd job logs for failure signatures and emits Drift incidents for routing through the incident pipeline.
triggers:
  - watch cron health
  - drift postmortem sweep
license: MIT
metadata: {"openclaw": {"emoji": "👁"}}
---

# drift-watcher — hourly cron health sweep

Phase 1 of the Drift incident ledger: detect cron failures by reading launchd log output and emit structured incident records.

## When this runs

- **Primary: cron.** `ai.openclaw.drift-watcher.plist` fires hourly 09:00–00:00 local.
- **Wrapper**: through `skill-wrapper --skill drift-watcher --agent main --trigger cron`.

## What it does

Invokes `${OPENCLAW_HOME}/bin/cron-postmortem-watch`:

1. Read recent launchd stdout/stderr logs for known plists.
2. Match against failure signatures (Nth consecutive error, timeout, missing artifact, etc.).
3. For each match, call `incident emit` with the appropriate taxonomy.
4. Apply green-path counter reset when a previously-failing job recovers.

## Exit codes

- `0` — sweep completed (incidents emitted as needed)
- `non-zero` — script-level error reading logs

## Files

- Script: `${OPENCLAW_HOME}/bin/cron-postmortem-watch`
- Plist: `$HOME/Library/LaunchAgents/ai.openclaw.drift-watcher.plist`
- This spec: `${OPENCLAW_HOME}/skills/drift-watcher/SKILL.md`

## Related

- `incident-emit` — direct downstream.
- `incident-analyze` / `incident-notify` — phases 2/3.
- `drift-learn` — phase 4 (weekly aggregation).
