---
name: gbrain-query
version: 1.1.0
description: >-
  Answer structured gbrain questions using search, query, pages, sources,
  backlinks, timeline, or graph traversal. Read-only. Not for writes — use
  brain-ops. Not for default memory recall; use QMD first.
license: MIT
triggers:
  - search gbrain
  - look in gbrain
  - gbrain backlinks
  - gbrain timeline
  - gbrain graph
  - what does gbrain know
  - gbrain lookup
  - check gbrain
mutating: false
---

# Gbrain Query

Use this skill for **read-only** gbrain lookups: search, query, pages, sources,
backlinks, timelines, graph relations, and citations. For write operations
(create, update, sync pages), use the `brain-ops` skill instead.

This skill does not replace QMD. For prior work, decisions, dates, people,
preferences, todos, or general memory recall, start with `qmd query`. Use
gbrain only when the user asks for gbrain/the brain or the task needs gbrain's
structured page/source/graph/timeline model.

As of 2026-05-28, durable workspace knowledge lives in `workspace*/wiki/`
(indexed by both QMD and gbrain). gbrain pages backed by wiki entries carry
structured graph + timeline + citation context that raw QMD retrieval lacks —
prefer gbrain second for "what cites this", "when was this decided", "what's
the source chain" questions.

## Environment

Codex/OpenClaw may run with a synthetic home directory. Always target the real
gbrain home:

```bash
GBRAIN_HOME=$HOME gbrain ...
```

Do not run bare `gbrain init`.

## Read Flow

1. Decompose the question into lookup types:
   - exact term, slug, person, project, or date
   - conceptual question
   - page/source lookup
   - backlink, graph, or timeline question
2. Start with search:

   ```bash
   GBRAIN_HOME=$HOME gbrain search "term"
   ```

3. Use hybrid query for conceptual questions:

   ```bash
   GBRAIN_HOME=$HOME gbrain query "question"
   ```

4. Read full pages only after search confirms relevance:

   ```bash
   GBRAIN_HOME=$HOME gbrain get <slug>
   ```

5. For relationships, prefer structured commands over prose search:

   ```bash
   GBRAIN_HOME=$HOME gbrain graph-query <slug> --type <link_type> --direction in
   GBRAIN_HOME=$HOME gbrain backlinks <slug>
   GBRAIN_HOME=$HOME gbrain timeline <slug>
   ```

6. Synthesize briefly and cite the source IDs/slugs visible in the output.

## Citation Rules

- Ground claims in gbrain results, not general knowledge.
- Cite pages as `<source_id>:<slug>` when source IDs are available.
- If a page includes inline citations, preserve the provenance in the answer.
- If results conflict, name the conflict and cite both sides.
- If gbrain lacks the information, say so directly.

## When To Use Brain Ops (writes) Instead

- The user asks to create, update, or write a brain page.
- You need to register a source or sync content.
- The task requires mutating gbrain state.

## When To Use QMD Instead

Use `qmd query` first when the user asks about:

- prior work or today's progress
- decisions and rationale
- personal preferences or standing directives
- todos, open threads, or dates
- workspace files outside structured gbrain pages

If QMD finds the relevant context and the task also needs gbrain source/page
verification, use gbrain second.

## Safety

- No ambient enrichment: do not run this on every inbound message.
- No silent writes: this skill is read-only unless another explicit workflow
  asks to save or update a brain page.
- Do not invent pages, sources, or relationships not present in results.
- Do not dump raw logs or private source content when a concise answer is enough.
- Redact secrets and unnecessary PII from quoted output.

## Search Quality

If results look wrong or missing:

```bash
GBRAIN_HOME=$HOME gbrain doctor --fast --json
```

Compare keyword and hybrid search for the same query before concluding the brain
does not contain the information.

## Output Format

```text
Answer: <direct answer>
Sources: <source_id:slug list>
Gaps: <only if relevant>
Conflicts: <only if relevant>
```