---
name: memory-capture-audit
version: 1.0.0
description: Nightly check that today's daily memory file was written by memory-capture (mc:v1 fingerprint + at least one mc:item stamp). Emits a Drift incident on freehand-write violations.
triggers:
  - audit memory capture
  - check memory fingerprint
license: MIT
metadata: {"openclaw": {"emoji": "🔍"}}
---

# memory-capture-audit — fingerprint enforcement

Catches freehand writes to `memory/YYYY-MM-DD.md` that bypass the `memory-capture` skill. The skill stamps every write with `<!-- mc:v1 -->` (file header) and `<!-- mc:item -->` (per-item). If a daily file exists without these stamps, something or someone wrote freehand — the historical root cause of bloated daily logs.

## When this runs

- **Primary: cron.** `ai.openclaw.memory-capture-audit.plist` fires daily at 22:25 (5 min before session-cleanup eod at 22:30, so violations are surfaced before the file is committed).
- **Wrapper**: through `skill-wrapper --skill memory-capture-audit --agent main --trigger cron`.

## What it does

Invokes `${OPENCLAW_HOME}/bin/memory-capture-audit.sh --emit-incident --quiet`:

1. Locate today's daily files across all configured workspaces (see `${OPENCLAW_HOME}/config/agents.map`).
2. For each: check for `<!-- mc:v1 -->` at the top and at least one `<!-- mc:item -->` in the body.
3. On violation, emit a Drift incident (`memory-capture-bypass-YYYY-MM-DD`).

## Exit codes

- `0` — no violations
- `1` — at least one violation (incident emitted)
- `2` — script-level error

## Files

- Script: `${OPENCLAW_HOME}/bin/memory-capture-audit.sh`
- Plist: `$HOME/Library/LaunchAgents/ai.openclaw.memory-capture-audit.plist`
- This spec: `${OPENCLAW_HOME}/skills/memory-capture-audit/SKILL.md`

## Related

- `memory-capture` — the skill whose fingerprints this audit enforces.
- `incident-emit` — downstream receiver of violations.
