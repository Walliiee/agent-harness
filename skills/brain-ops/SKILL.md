---
name: brain-ops
version: 1.1.0
description: >-
  Structured gbrain write operations: create pages, write-back, update sources,
  citations, sync. Not for queries — use gbrain-query for reads. Not for default
  memory recall; use QMD first there.
license: MIT
metadata: {"openclaw": {"emoji": "🧩"}}
mutating: true
triggers:
  - write to gbrain
  - gbrain write
  - gbrain write-back
  - update brain page
  - create brain page
  - gbrain sync
  - gbrain put
  - gbrain citation
---

# Brain Ops

Use this skill for **write** operations against the user's structured gbrain
knowledge base. For read/query operations, use the `gbrain-query` skill instead.
For prior work, decisions, dates, people, preferences, or todos, start with
`qmd query` unless the user specifically asks for gbrain.

## Environment

Codex/OpenClaw may run with a synthetic home directory. Always target the real
gbrain home explicitly:

```bash
GBRAIN_HOME=$HOME gbrain ...
```

The active brain is already configured at `$HOME/.gbrain/config.json` and
uses Postgres + pgvector. Do not run bare `gbrain init`.

## When to Use Brain Ops (writes)

- The user asks to save, create, update, or write a brain page.
- You need to register a source: `gbrain sources register`.
- You need to sync or update structured knowledge.
- You are writing durable structured knowledge to gbrain after the destination
  is clear.

## When to Use Gbrain Query (reads) Instead

- The user asks to look up, search, or query gbrain.
- You need backlinks, timeline, or graph traversal for context.
- The task is answer-only and does not need to write to gbrain.

## When to Use QMD Instead

- The user asks about prior work, preferences, decisions, todos, or dates.
- You need fast recall across workspace memory/wiki/agent files.
- The task is answer-only and does not need gbrain page/graph/timeline semantics.

If both are relevant, use QMD first for recall and gbrain second for structured
source/page verification.

## Write Flow

Gbrain writes are durable knowledge-base mutations. Only write when the user
asked to save/create/update a brain page, or when an existing workflow clearly
requires it.

Before writing:

1. Search for an existing page to avoid duplicates.
2. Confirm the correct source/workspace if multiple sources could fit.
3. Avoid PII/secrets. Use role-based identifiers where needed.
4. Preserve source attribution in the page body.

After writing, run the smallest relevant verification:

```bash
GBRAIN_HOME=$HOME gbrain get <slug>
```

If the write should be searchable immediately, run the existing sync path rather
than inventing a new one:

```bash
GBRAIN_HOME=$HOME gbrain sync --source <id>
```

## Safety

- Never run `gbrain init` from Codex/OpenClaw synthetic HOME.
- Never use gbrain as a reason to bypass QMD memory recall rules.
- Never dump gbrain logs without redacting admin/access tokens.
- Do not auto-enrich every inbound message. Surface or save only high-signal
  information that belongs in a durable brain page.
- Prefer read-only commands until the target page and source are clear.

## Report Format

For write work, report:

```text
Updated: <source_id:slug>
Verified: <command/result>
Follow-up: <only if needed>
```