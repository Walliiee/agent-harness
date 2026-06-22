---
name: dreaming-markdown-prune
version: 1.0.0
description: Weekly pruning of stale dreaming markdown into cold storage. Mutates workspace memory/dreaming files, so it must run through skill-wrapper for observable launchd execution.
triggers:
  - prune dreaming markdown
  - dreaming retention
license: MIT
metadata: {"openclaw": {"emoji": "🌙"}}
---

# dreaming-markdown-prune

Launchd maintenance wrapper for `${OPENCLAW_HOME}/bin/dreaming-markdown-prune --apply`.

## Contract

- Primary trigger: `$HOME/Library/LaunchAgents/ai.openclaw.dreaming-markdown-prune.plist`.
- Must run through `${OPENCLAW_HOME}/bin/skill-wrapper --skill dreaming-markdown-prune --agent main --trigger launchd`.
- This is not a documented exception: it mutates workspace markdown and should be in the skill-runs ledger.
- The wrapped command owns retention logic and idempotency.

## Verification

```bash
plutil -lint $HOME/Library/LaunchAgents/ai.openclaw.dreaming-markdown-prune.plist
${OPENCLAW_HOME}/bin/cron-wrapper-audit --verbose
```
