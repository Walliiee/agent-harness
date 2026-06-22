---
name: memory-canonicalize
version: 1.0.0
description: Shape raw items into a wiki-write-ready entry. Helper for memory-capture (promote-at-capture) and memory-promote. Returns canonical markdown + proposed INDEX.md line, or "update existing slug" verdict.
license: MIT
metadata: {"openclaw": {"emoji": "🧬"}}
triggers:
  - canonicalize memory
  - shape into wiki entry
  - prep for wiki-write
  - canonical wiki shape
---

# memory-canonicalize

Helper skill. Almost never invoked alone — called by `memory-capture` (when promote-at-capture fires, conf ≥ 0.85) and `memory-promote` (Mon/Wed/Fri sweep). Centralizes the wiki entry shape so the two callers never drift.

**Out of scope:** writing files (that's `wiki-write`), classifying daily items (that's `memory-capture` Step 2), scoring confidence (that's `memory-promote`). This skill only shapes.

## Inputs

Caller passes (as conversation context, not flags):
- **Raw content** — one or more bullets/paragraphs to land in a wiki entry.
- **Proposed category** — one of `agent-behaviors`, `projects`, `concepts`, `tools`, `people`. Caller already classified.
- **Proposed slug** (optional) — caller's guess at kebab-case filename.
- **Target agent wiki** — defaults to the main agent (`workspace/wiki/`). Specialist if `<agent>-only` rule applies (rare; per-agent vs cross-agent rule in `memory-capture/references/routing-table.md`).

## Workflow

### 1. Slug + collision check

- Normalize the proposed slug to kebab-case. Date-stamp project entries: `<topic>-YYYY-MM-DD.md` (matches existing convention — e.g. cold-stored `memory-system-redesign-2026-05-28.md`).
- Read `wiki/INDEX.md` for the target wiki.
- Search for the slug under the matching category section.
- **If slug exists** → return verdict `update` with the existing path. Caller should call `wiki-write` to append, not create.
- **If no slug match but content overlaps an existing entry** (jaccard ≥ 0.5 against the entry's first paragraph) → return verdict `update-suggested` with the candidate. Caller decides.
- **Otherwise** → verdict `create-new` and proceed.

### 2. Section structure per category

All entries follow `wiki-write` base format but with category-specific section adds:

| Category | Required sections (top to bottom) |
|---|---|
| `agent-behaviors` | Title, lede (2-3 sentences), **Why** (1-2 sentences), **How to apply** (2-4 bullets), Related, Sources |
| `projects` | Title, lede, **Why this matters**, **Key decisions** (or **Status**), one or more body sections specific to the project, Related, Sources |
| `concepts` | Title, lede, **Definition**, **How it works** (or **Example**), Related, Sources |
| `tools` | Title, lede, **What it is**, **How we use it**, **Caveats / known issues**, Related, Sources |
| `people` | Title, lede, **Role**, **Preferences**, **Context**, Related, Sources |

Always end with `_Last updated: YYYY-MM-DD_`.

### 3. Cross-link discovery

- Scan `wiki/INDEX.md` for slugs whose one-line description shares any token with the new entry's title or lede.
- Propose those as `[[slug]]` entries under `## Related`. Cap at 7 cross-links; rank by token-overlap count.
- Forward-references (slug doesn't yet exist) are allowed per the link-liberally rule.

### 4. INDEX line

Compose the INDEX entry exactly:

```
- [Title](category/filename.md) — one-line hook (≤ 100 chars).
```

The hook must be terse and scannable — same standard as MEMORY.md pointers. Reject anything ≥ 100 chars; rewrite.

### 5. Fingerprint stamps

Wiki entries do **not** get `mc:item` stamps — those are daily-log only. But if the raw input includes existing `<!-- mc:item -->` stamped bullets (because memory-promote is graduating items from daily), strip the stamps when shaping — they don't transfer.

### 6. Return shape

Return to caller:

```yaml
verdict: create-new | update | update-suggested
slug: <kebab-case>
path: workspace/wiki/<category>/<slug>.md
index_line: "- [Title](category/<slug>.md) — <hook>"
index_section: <category-display-name>   # e.g. "Agent Behaviors", "Projects"
markdown: |
  # Title
  ...full entry body...
related_candidates: [other-slug-1, other-slug-2]   # propose, don't decide
notes: optional, e.g. "Collision warning: slug 'X' exists in dev wiki"
```

The caller (`wiki-write`) takes this and lands the file. If verdict is `update`, caller reads the existing entry, appends new content, refreshes `_Last updated`.

## Quality checks (built into the shape)

Before returning, verify:
- Title is sentence case, no trailing punctuation.
- Lede ≤ 4 sentences. Strip narration ("I noticed", "we found"). Lead with the fact.
- No PII or personal names — apply the family-anonymized rule (`[[family-anonymized]]`).
- No `<!-- mc:item -->` stamps in body.
- `_Last updated:` matches today's date.
- INDEX line ≤ 100 chars.

If any check fails, fix in place. Don't return draft entries.

## Why this is a separate skill

If `memory-capture` and `memory-promote` each rolled their own shaping logic, they'd drift over time and we'd get inconsistent wiki entries. One canonical shaper means the wiki stays uniform regardless of which path landed each entry.

## Reference

- Wiki format baseline: `workspace/skills/wiki-write/SKILL.md`
- Category routing rules: `~/.openclaw/skills/memory-capture/references/routing-table.md`
- Locked architectural context: cold-stored at `workspace/cold-storage/wiki-projects-2026-06-11/memory-system-redesign-2026-05-28.md`
