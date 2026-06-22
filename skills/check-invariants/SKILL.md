---
name: check-invariants
version: 1.0.0
description: Cron maintenance wrapper for OpenClaw invariant checks. Kept for the cron job that invokes workspace/tools/check-invariants.sh through skill-wrapper.
triggers:
  - check invariants
  - invariant check
license: MIT
metadata: {"openclaw": {"emoji": "✅"}}
---

# check-invariants

Cron maintenance wrapper for `${OPENCLAW_HOME}/workspace/tools/check-invariants.sh`.

## Contract

- Primary trigger: OpenClaw cron job `Invariants check — weekly Sun 04:00`.
- Must run through `${OPENCLAW_HOME}/bin/skill-wrapper --skill check-invariants --agent main --trigger cron`.
- The wrapped script owns the invariant list and failure behavior.
- Preserve exit codes so cron failure handling and the skill-runs ledger agree.

## Verification

```bash
bash ${OPENCLAW_HOME}/workspace/tools/check-invariants.sh
openclaw cron list
```
