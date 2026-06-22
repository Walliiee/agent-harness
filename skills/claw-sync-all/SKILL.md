---
name: claw-sync-all
version: 1.0.0
description: Scheduled OpenClaw workspace/config/state mirror sync. Runs claw-sync-all.sh through skill-wrapper so DR sync work is observable; cron/launchd-driven, manual use only for sync repair.
triggers:
  - claw sync all
  - sync openclaw mirror
license: MIT
metadata: {"openclaw": {"emoji": "🔁"}}
---

# claw-sync-all

Launchd maintenance wrapper for `${OPENCLAW_HOME}/tools/claw-sync-all.sh`.

## Contract

- Primary trigger: `$HOME/Library/LaunchAgents/ai.openclaw.claw-sync-all.plist`.
- Must run through `${OPENCLAW_HOME}/bin/skill-wrapper --skill claw-sync-all --agent main --trigger launchd`.
- Sync scope and hook behavior live in the wrapped script and `wiki/tools/openclaw-dr-defense.md`.
- Keep the plist as a thin trigger: schedule, wrapper, command, logs.

## Verification

```bash
plutil -lint $HOME/Library/LaunchAgents/ai.openclaw.claw-sync-all.plist
${OPENCLAW_HOME}/bin/cron-wrapper-audit --verbose
```
