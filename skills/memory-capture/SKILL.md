---
name: memory-capture
version: 1.0.0
description: Parse and route memory. Use when asked to remember, save to memory, log this, capture notes, daily memory, brain dump, memory cleanup, lessons, decisions, or todos.
license: MIT
metadata: {"openclaw": {"emoji": "🧠"}}
triggers:
  - remember this
  - save this
  - save to memory
  - save this to memory
  - save to wiki
  - save as durable
  - add to memory
  - log this
  - capture this
  - daily memory
  - lesson learned
  - decision
  - todo
  - brain dump
  - things to remember
---

# memory-capture

## Workflow

Use this skill for explicit capture requests even when the wording is casual. "Save to memory", "remember", "log this", "capture this", "note this", "daily memory", "lessons", "decisions", and "todos" are all memory-capture requests unless the user clearly asks for a different storage system.

**Not for cleanup.** "Memory cleanup", "consolidate memory", "promote to wiki", "compact daily log" are NOT memory-capture triggers. Those operations belong to `memory-promote` (Mon/Wed/Fri sweep that graduates carry-forward items from daily → wiki) and `memory-compact` (EOD pass that reduces daily files crossing the 7-day boundary). If the user asks for cleanup, route to those skills, not here.

### 0. Start run telemetry

Before parsing, start a skill-runs record so memory-capture invocations show up in the ledger (`${OPENCLAW_HOME}/skill-runs/`) and feed the bloat-audit + promote-pipeline visibility:

```bash
PARENT_ARG=""
if [ -n "${OPENCLAW_RUN_ID:-}" ]; then
  PARENT_ARG="--parent-run-id $OPENCLAW_RUN_ID"
fi
RUN_ID=$(${OPENCLAW_HOME}/bin/skill-run start \
  --skill memory-capture \
  --agent <current-agent> \
  --trigger interactive \
  $PARENT_ARG)
export OPENCLAW_RUN_ID="$RUN_ID"
```

`<current-agent>` is one of the agents in `${OPENCLAW_HOME}/config/agents.map` (e.g. main, dev).

The `parent-run-id` propagation is mandatory when called from inside another wrapped skill (session-cleanup, memory-promote, etc.) — preserves the run tree so cross-skill flows are queryable.

### 1. Parse
Split input into individual items. One item = one thing to save.
Ignore filler words, conjunctions, and source attributions (handle those in the next step).

### 2. Classify
For each item, apply the routing table → `{baseDir}/references/routing-table.md`.
Flag ambiguous items (product vs. life principle) instead of guessing.

### 3. Deduplicate
Before writing, check if the item already exists in the target file. Skip if duplicate. Note it in confirm output.

### 4. Write
Write each item to all target files using the format in `{baseDir}/references/routing-table.md`.
**Always write to the daily log (`memory/YYYY-MM-DD.md`) regardless of other targets.**

**Header-merge (mandatory — kills daily-log bloat):**

Before appending a section to today's daily log:

1. Read the current daily log file (if it exists).
2. For each `##` section header you plan to add (e.g. `## Decisions`, `## What Happened`, `## Key Lessons`, `## Quick Wins`, `## Carry Forward`), scan the file for an existing header with the **same slug**.
3. **If found:** insert your new `<!-- mc:item -->` bullets at the bottom of that existing section. Do NOT create a duplicate `## Decisions` (or similar) below the existing one.
4. **If not found:** add the section in its canonical position (Decisions → What Happened → Key Lessons → Quick Wins → Carry Forward).

Three `## Decisions` blocks in one file is the symptom this rule prevents. The bloat audit (`bin/memory-bloat-audit.sh`) flags duplicate headers as a violation.

**Deterministic primitive (preferred over freehand merge):** if you have the bullet body for a single `##` section ready, pipe it through the merge-section CLI instead of doing the read-find-insert dance manually:

```bash
echo "- new bullet text" | ${OPENCLAW_HOME}/bin/memory-normalize \
  --merge-section "Carry Forward" --in-place /path/to/memory/YYYY-MM-DD.md
```

The CLI uses `lib/memory_invariants.merge_section()` — same library the audit reads. It (a) finds the existing `## Carry Forward` and appends, OR (b) creates it at the canonical position (Decisions → What Happened → Key Lessons → Quick Wins → Carry Forward), and (c) re-applies v1 + item stamps via `normalize()` so the file passes audit. Idempotency on the *bullet* content is still your job — dedupe before calling.

**Promote-at-capture (high-confidence items skip daily long-form):**

When an item's classification confidence is ≥ 0.85 AND the destination wiki category is clear (per routing-table.md), do NOT paste long-form into the daily log. Instead:

1. Invoke the `wiki-write` skill to land the entry in the right `workspace/wiki/<category>/<slug>.md`.
2. In the daily log, write only a one-line pointer:
   ```markdown
   - **[Title]** — [one-line summary] → see [wiki/<category>/<slug>.md] <!-- mc:item -->
   ```

Capture-time signals that warrant promote-at-capture (push toward ≥ 0.85):
- The item is a behavioral principle / agent rule (always X, never Y)
- The item is a long-form decision/lesson/post-mortem (>5 lines if you pasted it)
- The item is a reference card about a tool, daemon, system internal
- The user explicitly said "save to wiki" / "save as durable" / "this is permanent"
- The item matches an existing wiki slug (update via wiki-write rather than freehand into daily)

Lower-confidence items (0.60–0.85) stay daily-only and let the Mon/Wed/Fri `memory-promote` sweep re-score with cross-day signal (carry-forward count, jaccard match across daily files).

**YAML frontmatter (mandatory — Layer 2 pre-commit hook depends on it):**

When you create the daily log for the first time today, prepend this frontmatter block BEFORE the `# Memory — YYYY-MM-DD` H1 header:

```yaml
---
title: Memory — YYYY-MM-DD
type: daily-memory
created: YYYY-MM-DD
source: <agent>   # main | dev | ...
tags: [memory, daily]
---
```

`gbrain frontmatter validate` blocks any commit on a daily-log file without `---` on the first non-empty line. The `memory_invariants` library already preserves YAML frontmatter through `normalize()` and the v1-stamp insertion happens after it — so this is additive, not breaking. If you discover a daily file missing frontmatter, `memory-normalize --normalize --in-place` does NOT add it; use `gbrain frontmatter generate <path> --fix` to backfill deterministically (writes `.bak` first).

**Fingerprint stamps (mandatory — the audit depends on them):**
- When you create the daily log for the first time today, add `<!-- mc:v1 -->` as the second line of the file (after the `# Memory — YYYY-MM-DD` header, AFTER any YAML frontmatter). One per file, never duplicated.
- Append `<!-- mc:item -->` as a trailing comment on every bullet or sub-section you write into the daily log. One per item.
- If you are updating an existing item rather than adding one, leave the existing stamp in place; do not strip it.
- `bin/memory-capture-audit.sh` runs daily and emits a `memory-capture-bypass` Drift incident when a heading lacks a sentinel or the file lacks the v1 stamp. Skipping the stamp = the audit treats the write as freehand bypass.

**Provenance metadata (optional, additive — never alters `mc:item`):** when you know the provenance of a durable item, you MAY append a separate sibling marker AFTER the `mc:item` stamp so retrieval can later weigh staleness/confidence and resolve cross-agent conflicts:
```
- **[Title]** — summary → see [wiki/x.md] <!-- mc:item --> <!-- mc:meta source=<agent> conf=<0-1> ts=<YYYY-MM-DD> -->
```
The `<!-- mc:item -->` string MUST stay byte-identical (the audit greps it exactly); `mc:meta` is a second comment and is always optional. Schema: `reference/memory-metadata-schema.md`.

**Programmatic stamping (escape hatch when freehand drift slips in):** if you discover a daily file that's missing v1 / item stamps (e.g. you Edit/Write'd it directly), apply the invariants in one shot:

```bash
${OPENCLAW_HOME}/bin/memory-normalize --normalize --in-place /path/to/memory/YYYY-MM-DD.md
```

This is the same library the audit uses (`lib/memory_invariants`), so normalize → re-validate is guaranteed clean. Idempotent — safe to re-run.

### 5. Confirm
Output a compact summary — one line per item:
```
• [item] → [file(s)]
```
Flag duplicates (skipped) and ambiguous items (needs the user's decision) clearly.

### 6. End run telemetry

After writes + confirm, close the skill-runs record:

```bash
${OPENCLAW_HOME}/bin/skill-run end "$RUN_ID" \
  --outcome <success|partial|failure> \
  --task-completion <true|false> \
  --error-recovery true \
  --exit-code 0
```

Outcome rubric:
- **success** — all items routed and written cleanly, daily log has v1 + mc:item fingerprints, no dropped items.
- **partial** — some items skipped as duplicates or flagged ambiguous (still acceptable, but score lower).
- **failure** — file write error, missing required v1 stamp, classifier couldn't route any item, or wiki-write call failed during promote-at-capture.

`task-completion`: true if the user's request was fulfilled (their items are saved or correctly flagged); false if writes failed or all items were rejected without rescue.

`error-recovery`: true unless an explicit retry/fallback happened during the run.

## Reference
- Routing table + formats: `{baseDir}/references/routing-table.md`
- Canonical example: `{baseDir}/references/example-capture-2026-03-25.md`
- Invariants library + CLI: `${OPENCLAW_HOME}/lib/memory_invariants.py` (constants + `normalize()` + `validate()`); `${OPENCLAW_HOME}/bin/memory-normalize` (`--normalize --in-place <path>` for write-time, `--validate <path>` for audit-time). Source of truth for v1/item-stamp rules — if the rule changes, change the lib, not the skill.
