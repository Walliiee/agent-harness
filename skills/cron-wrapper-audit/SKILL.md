---
name: cron-wrapper-audit
version: 1.0.0
description: Weekly enforcement of the cron-thin-trigger-skill-does-work invariant. Walks every ai.{openclaw,gbrain}.*.plist and verifies it either routes through skill-wrapper or is in the documented exception allow-list. Emits a Drift incident on violation.
triggers:
  - audit cron wrappers
  - check cron pattern compliance
  - cron-wrapper-audit
license: MIT
metadata: {"openclaw": {"emoji": "🛡️"}}
---

# cron-wrapper-audit — invariant enforcement for cron pattern

Turns the wiki rule [[cron-thin-trigger-skill-does-work]] into a tested invariant. Without this script, the rule decays the next time someone adds a cron without reading the wiki entry.

## When this runs

- **Primary: cron.** `ai.openclaw.cron-wrapper-audit.plist` fires Sunday 04:45 (after `freshness-watch` at 05:00, before next-week's `drift-learn` at 04:30).
- **Wrapper**: through `skill-wrapper --skill cron-wrapper-audit --agent main --trigger cron`. Dogfoods the rule it enforces.

## What it does

For each `ai.{openclaw,gbrain}.*.plist` in `~/Library/LaunchAgents/`:

1. Use `plutil -extract` to read the plist's `Label` and `ProgramArguments.0`.
2. Classify:
   - `ProgramArguments[0]` contains `skill-wrapper` → **wrapped** ✓
   - Label matches the documented exception list → **exception** ✓
   - Otherwise → **violation** ✗
3. On any violation: emit a single rolled-up Drift incident (`source=cron-wrapper-audit`, `type=cron-bypass`, `severity=med`, `key=cron-wrapper-audit-YYYY-MM-DD`) listing every violating plist with its first program arg, and pointing to the wiki rule for remediation.

## Documented exceptions (live in the script)

These plist labels intentionally bypass skill-wrapper. Mirror the list in [[cron-thin-trigger-skill-does-work]] under "Documented exceptions"; if the two ever drift, the wiki entry is canonical.

- `ai.openclaw.gateway` — long-running daemon
- `ai.openclaw.skill-run-archive` — ledger maintainer (self-reference)
- `ai.openclaw.skill-run-reap` — ledger maintainer (self-reference)
- `ai.gbrain.mcp` — long-running daemon
- `ai.gbrain.postgres-sync` — gbrain internal observability
- `ai.gbrain.pg-backup` — gbrain internal observability
- `ai.gbrain.golden-eval` — gbrain internal observability
- `ai.gbrain.backups-push` — gbrain internal observability
- `ai.gbrain.maintenance-daily` — gbrain internal observability

Adding a new exception requires editing both the script's `EXCEPTIONS` array and the wiki rule's exceptions section in the same change.

## Exit codes

- `0` — clean, all plists compliant or exempt
- `1` — at least one violation (incident emitted in cron mode)
- `2` — script-level error (unreadable plist, missing dependencies)

## Inputs

- `--verbose` / `-v` — log every plist's verdict, not just violations.
- `--emit-incident` — emit a Drift incident on violation. Default off for manual runs; the plist passes this flag in cron mode.
- `--dry-run` — skip the `incident emit` call even when `--emit-incident` is set. Useful for testing.

## Files

- Script: `${OPENCLAW_HOME}/bin/cron-wrapper-audit`
- Plist: `~/Library/LaunchAgents/ai.openclaw.cron-wrapper-audit.plist`
- Rule: `${OPENCLAW_HOME}/workspace/wiki/agent-behaviors/cron-thin-trigger-skill-does-work.md`
- This spec: `${OPENCLAW_HOME}/skills/cron-wrapper-audit/SKILL.md`

## Related

- [[cron-thin-trigger-skill-does-work]] — the rule this enforces.
- `incident-emit` — downstream Drift pipeline receiver of violations.
- `drift-watcher`, `drift-learn` — incident pipeline peers.
