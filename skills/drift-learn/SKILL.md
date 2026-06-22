---
name: drift-learn
version: 1.0.0
description: Weekly Drift incident learning pass. Reads accumulated incidents, clusters them, and produces compound lessons (Phase 4 of the Drift incident pipeline).
triggers:
  - learn from drift incidents
  - drift weekly review
license: MIT
metadata: {"openclaw": {"emoji": "🧠"}}
---

# drift-learn — weekly incident clustering pass

Phase 4 of the Drift incident ledger: take a week of `${OPENCLAW_HOME}/incidents/YYYY-MM-DD/*.md` records and produce compound lessons (patterns that recur, root causes, recommended skill patches).

## When this runs

- **Primary: cron.** `ai.openclaw.drift-learn.plist` fires Sunday 04:30.
- **Wrapper**: through `skill-wrapper --skill drift-learn --agent main --trigger cron`.

## What it does

Invokes `${OPENCLAW_HOME}/bin/incident-learn --verbose`:

1. Scan the past 7 days of incident records.
2. Cluster by taxonomy (cron-postmortem, memory-capture-bypass, etc.).
3. Generate lesson candidates with LLM analysis.
4. Append to `${OPENCLAW_HOME}/incidents/lessons/YYYY-WW.md`.

## Exit codes

- `0` — success or partial success
- `non-zero` — script-level failure

## Files

- Script: `${OPENCLAW_HOME}/bin/incident-learn`
- Plist: `$HOME/Library/LaunchAgents/ai.openclaw.drift-learn.plist`
- This spec: `${OPENCLAW_HOME}/skills/drift-learn/SKILL.md`

## Related

- `drift-watcher` — emits incidents this skill consumes.
- `incident-emit`, `incident-analyze`, `incident-notify` — incident pipeline phases 1-3.
