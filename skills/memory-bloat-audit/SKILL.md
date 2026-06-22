---
name: memory-bloat-audit
version: 1.0.0
description: Mon/Wed/Fri invariant check of the memory system. Catches stale daily files (compact didn't fire), freehand writes (memory-capture bypassed), stuck promote-queue entries (review backlog), and structural gaps (a workspace never migrated). Single rolled-up Drift incident on any violation.
triggers:
  - audit memory system
  - check memory invariants
  - memory-bloat-audit
license: MIT
metadata: {"openclaw": {"emoji": "📐"}}
---

# memory-bloat-audit — invariant enforcement for the memory system

Same compound pattern as [[cron-thin-trigger-skill-does-work]]'s `cron-wrapper-audit` but for the memory architecture. Catches drift between the documented memory-system design and reality.

## When this runs

- **Primary: cron.** `ai.openclaw.memory-bloat-audit.plist` fires Mon/Wed/Fri 22:45 — after `memory-promote` at 22:00 and `session-cleanup` eod at 22:30, so it sees the post-graduation state.
- **Wrapper**: through `skill-wrapper --skill memory-bloat-audit --agent main --trigger cron`.

## Invariants (v1)

| Invariant | Test | Likely cause when it fires |
|---|---|---|
| `stale-daily` | Daily file age > 8d, no `<!-- mc:compacted -->` marker, has bullet content | compact's safety guard skipped a file with content but no wiki pointers — needs retro-promote (or legacy backfill) |
| `freehand-write` | Today's daily file has bullets but no `<!-- mc:v1 -->` marker | something bypassed `memory-capture` (defense-in-depth duplicate of memory-capture-audit) |
| `stuck-queue` | `promote-queue.md` has `## YYYY-MM-DD` entry > 14d old in the `## Queue` section | the user hasn't reviewed the queue; backlog signal |
| `wiki-empty` | a configured workspace's `wiki/` has < 5 entries | a never-migrated workspace; sentinel for a missing one-shot migration |

Future invariants (not in v1): wiki size cap, one-fact-one-home jaccard check, QMD freshness lag.

## What it does

1. Walk all configured workspaces (see `${OPENCLAW_HOME}/config/agents.map`) and apply each invariant.
2. Print a summary line: `[memory-bloat-audit] today=YYYY-MM-DD inv1=N inv2=N ... total=N`.
3. List violations grouped by invariant.
4. If violations > 0 AND `--emit-incident`: emit a single rolled-up Drift incident (`source=memory-bloat-audit`, `type=memory-invariant-violation`, `severity=med`, `key=memory-bloat-audit-YYYY-MM-DD`) listing every violation with the recommended fix path.

## Exit codes

- `0` — clean
- `1` — one or more violations (incident emitted in cron mode)
- `2` — script-level error

## Inputs

- `--emit-incident` — emit Drift incident on violation. Default off; the plist passes it.
- `--dry-run` — skip the actual `incident emit` call even with `--emit-incident`. Test-friendly.
- `--verbose` / `-v` — log each violation as encountered, not just in the final summary.

## Files

- Script: `${OPENCLAW_HOME}/bin/memory-bloat-audit` (Python, ~210 lines)
- Plist: `$HOME/Library/LaunchAgents/ai.openclaw.memory-bloat-audit.plist`
- This spec: `${OPENCLAW_HOME}/skills/memory-bloat-audit/SKILL.md`

## Fix paths

The audit ships fix paths in its incident body so future-me doesn't have to reverse-engineer the resolution:

- `stale-daily` → `bin/memory-promote-sweep --window 14` to harvest, then `bin/memory-compact-sweep --apply`.
- `freehand-write` → re-run today's writes through `memory-capture`; rewrite file with fingerprint stamps.
- `stuck-queue` → review `memory/promote-queue.md`; follow the in-file promote/drop/defer instructions.
- `wiki-empty` → one-shot migration via `memory-import` targeting the affected workspace.

## Related

- [[memory-promote]], [[memory-compact]], [[memory-capture]] — the skills whose work this audit verifies.
- `incident-emit` — Drift pipeline receiver of violations.
- `cron-wrapper-audit` — sibling invariant enforcer for the cron pattern.
