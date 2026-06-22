---
name: frontmatter-backfill
version: 1.0.0
description: Scheduled markdown frontmatter backfill across OpenClaw workspaces. Runs the deterministic backfill command through skill-wrapper because it mutates files.
triggers:
  - frontmatter backfill
  - repair frontmatter
license: MIT
metadata: {"openclaw": {"emoji": "🧾"}}
---

# frontmatter-backfill

Launchd maintenance wrapper for `${OPENCLAW_HOME}/bin/openclaw-frontmatter-backfill --apply`.

## Contract

- Primary trigger: `~/Library/LaunchAgents/ai.openclaw.frontmatter-backfill.plist`.
- Must run through `${OPENCLAW_HOME}/bin/skill-wrapper --skill frontmatter-backfill --agent main --trigger launchd`.
- This is not a documented exception: it mutates markdown frontmatter and should be observable.
- The wrapped command owns file selection, write behavior, and safety checks.

## Verification

```bash
plutil -lint ~/Library/LaunchAgents/ai.openclaw.frontmatter-backfill.plist
${OPENCLAW_HOME}/bin/cron-wrapper-audit --verbose
```
