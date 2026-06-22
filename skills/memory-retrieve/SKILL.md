---
name: memory-retrieve
version: 1.0.0
description: Use when you need a fact, decision, project state, or person that may be in memory or the wiki — not from training data or web search. Load the body for the retrieval order; don't improvise it.
triggers:
  - find in memory
  - search durable knowledge
  - look up in wiki
  - memory-retrieve
license: MIT
metadata: {"openclaw": {"emoji": "🔎"}}
---

# memory-retrieve — durable knowledge lookup

The single sanctioned entry point for retrieving from the durable memory cortex (wiki + daily memory). Wraps the two underlying retrieval systems and enforces the order.

## When to use

- An agent (or the user) needs a fact, decision, principle, project state, or person reference that may already be in the wiki or recent daily memory.
- **Before web search** for anything that could plausibly live locally.
- **Before answering from training data** — local knowledge is current; training data is not.

## The order — locked

1. **QMD first** (`qmd query`). Fast hybrid (BM25 + vector + reranking) across all indexed collections. Returns in <1s. Sufficient for ~90% of retrievals.
2. **gbrain second** (`gbrain query`). Only escalate when QMD returns zero hits AND the question needs structured reasoning: timelines, relationship graphs, citation chains, multi-hop reference following.

Reasoning: QMD updates every 30 min via `qmd-sync`; gbrain syncs hourly via `ai.gbrain.postgres-sync`. QMD's coverage is broader (daily + wiki), gbrain's structure is deeper (graph + pages + sources). Most lookups don't need the depth.

## Provenance-aware ranking (when hits carry `<!-- mc:meta ... -->`)

QMD/gbrain rank by relevance/recency, not trust. When a returned item carries provenance metadata, weigh it before relying on it:

- **Conflict between two hits → prefer higher `conf`, then newer `ts`.** Don't average contradictory facts; pick the most-trusted/most-recent and note the conflict.
- **Item past its `mc:meta decay` date → treat as needs-verification, not ground truth.** Confirm against current state before asserting it.
- **A promotion marker with `recalls=0` that is months old is low-signal** — don't over-weight it just because it surfaced.

Schema: `reference/memory-metadata-schema.md`. The monthly `bin/stale-memory-report` surfaces decayed / low-conf / never-recalled items for pruning. This is advisory weighting on top of the backend ranking — it never changes the QMD-first/gbrain-second order above.

## How to invoke

```bash
~/.openclaw/bin/memory-retrieve "<query>" [flags]
```

| Flag | Effect |
|---|---|
| (default) | QMD only |
| `--escalate` | QMD first; if zero hits, fall back to gbrain |
| `--qmd-only` | Force QMD only (explicit) |
| `--gbrain-only` | Skip QMD entirely (rare — only when you specifically need the graph) |
| `--collection <name>` | Scope QMD to a single collection (`wiki-main`, `memory-main`, `agents-dev-wiki`, etc.) |
| `-n <limit>` | Result count (default 10) |
| `--verbose` / `-v` | Show invocation details |

## Output

Whatever `qmd query` / `gbrain query` produce. The wrapper does not reformat — preserves raw output so docids, paths, and ranks remain visible.

## When NOT to use

- **Writing**: use `wiki-write` (durable) or `memory-capture` (daily).
- **Cross-agent search of a specific agent's silo**: prefer the explicit XDG-wrapped `qmd` invocation documented in `skills/qmd/SKILL.md` so you control the silo identity.
- **Production data lookups**: this is for *knowledge* (decisions, principles, references), not transactional data.

## Why this skill exists

Without a canonical entry point, every agent invents its own retrieval pattern. Some used `memory_search` (deprecated), some hit `gbrain` first (wasteful), some skipped local lookup entirely (regressed to training data). This skill is the one place the order is enforced; future tweaks to the order live here, not in every agent's prompt.

## Files

- Script: `~/.openclaw/bin/memory-retrieve`
- This spec: `~/.openclaw/skills/memory-retrieve/SKILL.md`

## Related

- `qmd` — the underlying fast-recall skill.
- `gbrain-query` — the underlying structured/graph skill.
- `wiki-write` — the writing counterpart for durable knowledge.
- `memory-capture` — the writing counterpart for daily memory.
- `agent-behaviors/search-discipline.md` — the principle this skill implements.
