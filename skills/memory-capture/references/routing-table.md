# Routing Table — memory-capture

Maps each input type to target file(s). Apply this table during the Classify step.

> **Architecture (2026-05-28):** Daily files = hippocampus (7-day capture window). Wiki = cortex (durable, indexed by QMD + gbrain). Promotion pipeline (memory-promote, runs Mon/Wed/Fri) graduates carry-forward items from daily → wiki. This table tells memory-capture **what to route, where, and when to promote at capture-time vs leave for the sweep**.

## Promote-at-capture threshold

When classifying an item, score confidence in destination + shape:

- **conf ≥ 0.85 AND clear category** → write to wiki immediately via `wiki-write` skill, leave one-line pointer in daily log. Long-form, decisions with clear scope, explicit "save to wiki" requests, and items matching an existing wiki slug all hit this.
- **conf 0.60–0.85 OR multiple candidate destinations** → daily log only. `memory-promote` decides on Mon/Wed/Fri sweep.
- **conf < 0.60 AND no carry-forward** → daily log only. Likely drops on 7-day compact.

Never write directly to wiki bypassing `wiki-write` — that skill owns format, INDEX.md updates, and `_Last updated_` stamping.

## Input Types → Target Files

| Input type | Classification signal | Target file(s) |
|---|---|---|
| Behavioral principle / agent rule | "Always X" / "Never Y" — persistent rule about how agents should work | `workspace/wiki/agent-behaviors/<slug>.md` via wiki-write (promote-at-capture if conf ≥ 0.85) + daily log |
| Project decision / lesson / outcome | Decision made, lesson learned, milestone, post-mortem | `workspace/wiki/projects/<slug>.md` via wiki-write (promote-at-capture if conf ≥ 0.85) + daily log. Per-agent variant: `workspace-<agent>/wiki/projects/` if scoped to one agent's domain |
| Tool / system reference | Reference card for a tool, daemon, API, system internal | `workspace/wiki/tools/<slug>.md` via wiki-write (promote-at-capture if conf ≥ 0.85) + daily log |
| Concept / framework / model | Mental model, conceptual reference, framework | `workspace/wiki/concepts/<slug>.md` via wiki-write (promote-at-capture if conf ≥ 0.85) + daily log |
| Person reference | Name + why relevant + ongoing relevance | `workspace/wiki/people/<slug>.md` via wiki-write if it's a recurring entity; otherwise daily log only |
| Book/source insight | Insight attributed to a book or source | Route the insight by its shape (principle/concept/tool); attribute source inline in destination file |
| Actionable todo | Something to do in future | `<current-workspace>/tasks/current.md` |
| Startup-critical fact | Brand-new session needs this on day 1 | Daily log + flag for manual review of `$HOME/.claude/projects/<project>/memory/MEMORY.md` (session-context pointer). Do **not** auto-write MEMORY.md — it's a curated thin pointer, not an append target. |
| Everything | All items regardless of type | `memory/YYYY-MM-DD.md` (current-workspace daily log) — ALWAYS, no exceptions |

## Per-agent vs cross-agent

- **Default** → cross-agent: `workspace/wiki/<category>/` (the main agent's wiki). Use this when the item applies to multiple agents or is general infrastructure / behavior.
- **Per-agent** → `workspace-<agent>/wiki/<category>/`. Use only when the item is explicitly scoped to one agent's domain (e.g., a dev-only build-discipline rule).
- **Ambiguous?** → the main wiki. Cross-agent reusable beats agent-scoped silo by default.

## Format Reference

### Wiki entries (via wiki-write)

`wiki-write` skill owns the format. Standard shape:

```markdown
# [Title]

[2-3 sentences. What is this, why does it matter.]

## Key Points
- Point 1
- Point 2

## Related
- [[other-entry]]

## Sources
- Session: YYYY-MM-DD
- [url or file path]

_Last updated: YYYY-MM-DD_
```

50–150 lines max. Cross-link with `[[name]]` when relevant entries exist. wiki-write also updates `wiki/INDEX.md`.

### tasks/current.md

```markdown
- [ ] **[Item name]** — [brief context]
  - Added: YYYY-MM-DD
```

### Daily log (`memory/YYYY-MM-DD.md`)

MUST follow this structure. The `<!-- mc:v1 -->` line and `<!-- mc:item -->` trailing comments are MANDATORY — `bin/memory-capture-audit.sh` uses them to detect freehand-write bypass.

```markdown
# Memory — YYYY-MM-DD (Weekday)
<!-- mc:v1 -->

## Decisions
- **[Decision name]** — [What was decided and why] <!-- mc:item -->

## What Happened
- [Time/Event] — [Concise summary] <!-- mc:item -->

## Key Lessons
1. **[Lesson]** — [What broke/what worked]. Fix: [if applicable]. <!-- mc:item -->

## Quick Wins
- [Win] — [What got done easily] <!-- mc:item -->

## Carry Forward
- [ ] **[Task]** — [Context + priority]. Deadline: [if any]. <!-- mc:item -->
```

When an item is promoted at capture-time (conf ≥ 0.85), the daily-log entry becomes a pointer:

```markdown
- **[Decision]** — [one-line summary] → see [wiki/projects/<slug>.md] <!-- mc:item -->
```

Don't paste long-form into the daily log if you're also writing to wiki — that's exactly the duplication the architecture is built to prevent.

### Stamp rules

- `<!-- mc:v1 -->` appears exactly once, as the second line (after `# Memory — ...`).
- `<!-- mc:item -->` trails every bullet or sub-section item you write. One per item.
- When updating an existing item, leave the existing stamp in place — do not strip it.
- Auditor counts: `headings == ## sections`, `item_stamps == <!-- mc:item --> lines`. If `item_stamps < headings`, the file is flagged.

### Header-merge rule (mandatory — kills daily-log bloat)

Before appending to today's daily log:

1. Scan the file for an existing `##` header with the same slug as the section you'd add.
2. If found: merge new `<!-- mc:item -->` bullets into that section. Do **not** create a duplicate `## Decisions` (or `## What Happened` etc.) below an existing one.
3. If not found: add the section in its canonical position (Decisions → What Happened → Key Lessons → Quick Wins → Carry Forward).

Three `## Decisions` blocks in one file is the symptom; header-merge is the cure.

## AI Optimization Check (apply to EVERY item before writing)

1. **Structure over prose** — Is this a bullet point, not a paragraph?
2. **Pointers over copies** — Does this reference a source instead of duplicating? If it would also go to wiki, the daily log gets a pointer, not a copy.
3. **Machine-readable** — Are section headers consistent? Is metadata present?
4. **Valid references** — Do all links/paths resolve?
5. **Executable** — Can a future AI agent act on this without asking questions?

If any check fails, rewrite the item before saving.

## Domain-Specific Destinations

Beyond the generic categories above, a deployment may add its own domain-specific routing rows (e.g. a per-agent workspace with its own specialized files). When you add such a row, follow the same shape as the table above: `Input type | Classification signal | Target file`, route to a `<per-agent workspace>/...` path, and make sure the item still lands in the current-workspace daily log as well.

## Deduplication Rule

Before writing to any target file:

1. **Item-level dedup** — check if the item (or near-identical version) already exists. If yes: skip the write, note "already exists" in confirm output.
2. **Header-level dedup** (daily log only) — apply the header-merge rule above.
3. **Wiki-level dedup** — wiki-write will check `wiki/INDEX.md` before creating a new page. If a matching slug exists, update the existing entry instead.

## Ambiguity Rule

If an item could land in multiple destinations — flag it for the user's decision. Do not guess.

Output: `⚠️ [item] — could be agent-behavior, project, or concept. Which?`

Items flagged here also default to daily-log-only (conf < 0.85), letting memory-promote re-classify with cross-day signal.
