---
name: openclaw-invariants-check
version: 1.0.0
description: Weekly OpenClaw invariant check for feature flags, routing, frontmatter regressions, router coverage, and root MEMORY.md hygiene. Launchd-driven through skill-wrapper.
triggers:
  - openclaw invariants
  - check invariants
license: MIT
metadata: {"openclaw": {"emoji": "✅"}}
---

# openclaw-invariants-check

Launchd maintenance wrapper for `${OPENCLAW_HOME}/bin/openclaw-invariants-check`.

## Contract

- Primary trigger: `~/Library/LaunchAgents/ai.openclaw.invariants-check.plist`.
- Must run through `${OPENCLAW_HOME}/bin/skill-wrapper --skill openclaw-invariants-check --agent main --trigger launchd`.
- This is a discrete check with an exit code, so it belongs in the skill-runs ledger.
- The wrapped script owns the invariant list and failure reporting.

## Verification

```bash
plutil -lint ~/Library/LaunchAgents/ai.openclaw.invariants-check.plist
${OPENCLAW_HOME}/bin/cron-wrapper-audit --verbose
```
