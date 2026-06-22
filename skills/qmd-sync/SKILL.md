---
name: qmd-sync
version: 1.0.0
description: Re-index and re-embed QMD across all agent silos. Closes the freshness gap so new wiki/memory writes reach the vector index within 30 minutes. Cron-driven; manual invocation rarely needed.
triggers:
  - sync qmd
  - reindex qmd
  - refresh qmd embeddings
license: MIT
metadata: {"openclaw": {"emoji": "🔁"}}
---

# qmd-sync — QMD index + embedding refresh

Keeps every QMD silo (the main agent + any specialist agents) current so promote-at-capture writes and memory-promote outputs become searchable within 30 minutes instead of waiting for a manual run.

## When this runs

- **Primary: cron.** `ai.openclaw.qmd-sync.plist` fires every 30 minutes (`StartInterval=1800`), 24/7 — embedding cost is small.
- **Secondary: manual.** Invoke when a write needs to be searchable immediately (rare). Use `bin/qmd-sync --agent <name>` to scope.

## What it does

For each agent listed in `${OPENCLAW_HOME}/config/agents.map` (e.g. `main`, `dev`):

1. Set `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` to that agent's `${OPENCLAW_HOME}/agents/<agent>/qmd/` silo.
2. `qmd update` — re-scan all configured collections, pick up added/modified/deleted markdown.
3. `qmd embed` — generate embeddings for any new chunks lacking vectors.

Per-agent results are collected; an aggregate summary line is printed.

## Exit convention

- `0` — all agents synced, OR at least one succeeded (partial-success counts as success, per the memory-promote convention).
- `1` — every agent failed (hard failure). skill-wrapper default success check picks this up.
- `2` — bad arguments.

A skipped silo (missing `xdg-config` dir) is not a failure.

## Inputs

`bin/qmd-sync` accepts:

- `--verbose` / `-v` — show full `qmd update` and `qmd embed` output instead of summary only.
- `--agent <name>` — scope to a single agent silo.
- `--skip-embed` — run `qmd update` only; useful when embeddings aren't the bottleneck.

## Outputs

- `${OPENCLAW_HOME}/logs/qmd-sync.log` and `qmd-sync.err.log` — launchd captures stdout/stderr.
- One-line summary on stdout: `[qmd-sync] ok=N failed=M skipped=K ok=[…] failed=[…]`.
- Skill-runs ledger entry per invocation (recorded by skill-wrapper).

## Files

- Script: `${OPENCLAW_HOME}/bin/qmd-sync` (bash, ~120 lines).
- Launchd: `$HOME/Library/LaunchAgents/ai.openclaw.qmd-sync.plist`.
- This spec: `${OPENCLAW_HOME}/skills/qmd-sync/SKILL.md`.

## Not for

- Forcing re-embedding of unchanged content — use `qmd embed -f` manually if needed.
- One-off collection adds — use `qmd collection add` directly per-silo.
- Search itself — that's the `qmd` skill.

## Related

- `memory-promote` — produces the wiki writes this skill makes searchable.
- `memory-capture` — promote-at-capture also produces wiki writes that need indexing.
- `qmd` — search-side counterpart.
