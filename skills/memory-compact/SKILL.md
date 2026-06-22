---
name: memory-compact
version: 1.0.0
description: Collapse daily memory files older than the 7-day active window into thin records. Keeps wiki-pointered/[keep]-marked Decisions and Key Lessons, drops What Happened and Carry Forward, preserves the original in `memory/cold-storage/`.
triggers:
  - compact memory
  - graduate daily memory
  - thin out old memory
license: MIT
metadata: {"openclaw": {"emoji": "📚"}}
---

# memory-compact — 7-day graduation of daily files

After a daily file crosses the 7-day active window, **promote-at-capture** and the Mon/Wed/Fri **memory-promote** sweep have had every chance to graduate durable content into the wiki. What's left is either:

- already wiki-pointered (`→ see [wiki/...]`) — these are pointers to durable content
- explicitly marked `[keep]` — the user wants this in the daily record indefinitely
- ephemeral (`What Happened`, `Carry Forward`) — drops on compact

This skill enforces that graduation. The file shrinks to a thin record; the full original moves to `memory/cold-storage/` (which QMD excludes from indexing).

## When this runs

- **Primary: dedicated command cron.** The "Memory compact — daily 23:45" cron runs `bin/memory-compact-sweep --apply` deterministically (a command cron — runs the script directly, no model judgment, can't hallucinate success). Wired 2026-06-13. session-cleanup may still surface compaction needs, but the nightly command cron is the authoritative runner.
- **Manual: backfill.** `bin/memory-compact-sweep --apply` to retroactively compact files older than 7 days. Phase 0d-3 will run this against the legacy 2026-05-17 through 2026-05-21 files **after** a retro-promote pass.

## What it does

For each daily file `workspace*/memory/YYYY-MM-DD.md` older than 7 days (and lacking a `<!-- mc:compacted ... -->` marker):

1. **Backup** original to `workspace*/memory/cold-storage/YYYY-MM-DD.md`. Idempotent — skipped if cold-storage copy already exists.
2. **Rewrite** the daily file to:
   - Title line (`# Memory — YYYY-MM-DD …`)
   - `<!-- mc:v1 -->` marker
   - `<!-- mc:compacted YYYY-MM-DD -->` stamp (today)
   - `## Decisions` — only bullets containing `→ see [wiki/...]` or `[keep]`. Section omitted if zero bullets survive.
   - `## Key Lessons` — same filter rule.
   - `## Reference` — kept verbatim (skill-run IDs, source links).
   - Footer pointer line to cold-storage.
3. **Drop entirely**: `## What Happened`, `## Carry Forward`, any unknown section.

Sections are detected by `## Header` at the start of a line. Unknown headers (legacy files often have free-text section names like "## Drift Incident System") drop by default — durable content should already be wiki-pointered.

## Conventions

- **Dry-run by default.** `bin/memory-compact-sweep` without `--apply` prints the plan only. `--apply` writes.
- **Idempotent.** Files with `<!-- mc:compacted -->` are skipped; re-running is a no-op.
- **Exit codes** (matches memory-promote-sweep / qmd-sync):
  - `0` — all files written, or at least one written when others failed
  - `1` — every targeted file failed
  - `2` — bad arguments
- **Cold-storage is QMD-excluded.** The `memory-main` collection ignore pattern includes `cold-storage/**`, so compacted content disappears from search by design. If you need it back, copy from cold-storage to a wiki page.

## Inputs

`bin/memory-compact-sweep` accepts:

- `--apply` — write changes; without this, dry-run.
- `--workspace <name>` — scope to one workspace (default: all covered workspaces).
- `--max-age-days N` — override the 7-day window (default: 7).
- `--include-recent` — DESTRUCTIVE; compact files <7d old. For backfill testing only.
- `--verbose` / `-v` — preview the first 20 lines of each planned compact output.

## Outputs

Per-file plan line:
```
[PLAN] workspace/memory/2026-05-21.md  age=7d  lines 29→6 (-79%)  bullets kept=0 dropped=11
```

Summary on apply:
```
[memory-compact] applied: written=N failed=M
```

## Legacy file gotcha (important)

The 2026-05-17 through 2026-05-21 files were written **before** the new architecture. They contain durable decisions (Drift Incident System Phase 1+2+3 shipping, etc.) that were never wiki-promoted because the architecture didn't exist yet. Running `--apply` on these **right now** would compact them to a tombstone, hiding the content in cold-storage where QMD can't search it.

**Do not `--apply` against legacy files until Phase 0d-3 retro-promote runs first.** Phase 0d-3 (a one-shot pass invoking memory-promote-sweep with a lower threshold over the 2026-05-17 → 2026-05-21 window) will harvest those decisions to the wiki, after which compact is safe.

For Phase 0d-1 (this build) and Phase 0d-2 (session-cleanup wire-in), the only files compacted will be **post-architecture** dailies — i.e., files born after 2026-05-28 with proper mc:item stamps and wiki pointers.

## Files

- Script: `~/.openclaw/bin/memory-compact-sweep` (Python, ~290 lines)
- This spec: `~/.openclaw/skills/memory-compact/SKILL.md`
- Wire point: session-cleanup eod (Phase 0d-2, pending)

## Not for

- Live daily files (<7 days old) — they're still in the capture window.
- Wiki entries — those are durable; this skill only touches `memory/YYYY-MM-DD.md`.
- Dreams (`memory/dreaming/`), working notes (`memory/working/`), archives — already excluded.

## Related

- `memory-promote` — produces the wiki pointers this skill preserves.
- `memory-capture` — promote-at-capture writes wiki entries during normal capture.
- `qmd-sync` — keeps QMD aware of new wiki pointers within 30 min, so a freshly-pointered bullet is indexed before compact runs.
- `session-cleanup` (eod path) — calls this skill at end-of-day (Phase 0d-2 pending).
