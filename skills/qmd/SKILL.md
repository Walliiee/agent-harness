---
name: qmd
version: 2.0.0
description: Search local markdown knowledge bases — memory, wiki, agent context, skills, and project docs — using QMD hybrid search. Use before web search when the answer may already be indexed locally.
triggers:
  - search my notes
  - search memory
  - what do I know about
  - look up in wiki
  - find in knowledge base
  - search knowledge base
license: MIT
metadata: {"openclaw": {"emoji": "🔍"}}
---

# QMD — Local Knowledge Base Search

QMD is the local vector+keyword search engine over the user's workspaces. Use it **before** answering questions that may already be documented — especially for context about people, projects, decisions, and past work.

## Workflow

The workflow is always:

1. **Search** for candidate documents.
2. **Retrieve** the full source with `qmd get` or `qmd multi-get`.
3. **Answer** from retrieved text, citing paths or docids.

**Do not answer from snippets alone** when the user needs facts, decisions, quotes, or nuance. Snippets are only leads.

When reporting what you retrieved, a compact note is enough; do not paste whole files unless needed:

```text
Retrieved: #abc123 wiki/projects/GenAICategorizer.md, #def432 memory/2026-05-26.md
```

## Pick the right search mode

| Mode | Command | When to use |
|---|---|---|
| BM25 keyword | `qmd search` | Exact words, titles, names, code symbols, rare phrases |
| Hybrid + rerank | `qmd query` | Indirect wording, conceptual recall, best quality |
| Structured | `qmd query` with `lex:/vec:/hyde:` fields | Hard searches needing exact anchors + semantic recall |

**Simple lookup:**
```bash
qmd search "challenger crew project status" -n 10
qmd search '"GenAI Categorizer"' -c wiki-main -n 5
```

**Semantic concept lookup:**
```bash
qmd query "decision quality depends on surfacing assumptions and context" -n 10
```

**Structured query (hard searches):**
```bash
qmd query $'intent: Find the concept note about metrics as instruments without letting OKRs replace judgment.\nlex: cockpit instruments OKR Goodhart metrics judgment\nvec: data informed not metric driven product judgment\nhyde: A concept note says metrics are useful like cockpit instruments, but leaders should remain data-informed rather than metric-driven because OKRs and dashboards can Goodhart product judgment.'
```

Structured query fields:
- `intent:` states what you are trying to find and what to avoid.
- `lex:` exact terms, aliases, titles, and rare words.
- `vec:` paraphrases the idea in natural language.
- `hyde:` describes the document or answer that would satisfy the request.

## Retrieve sources

```bash
qmd get "#abc123"                        # by docid from search results
qmd get "wiki/projects/GenAICategorizer.md" --full  # by path
qmd multi-get "#abc123,#def432" --md     # batch by docids
qmd multi-get 'memory/2026-05-*.md' -l 80  # glob batch
```

Use `multi-get` when comparing several hits or gathering context across pages. Use `--full` when the exact source matters.

## Collections by agent

Each agent has its own QMD index with XDG-isolated config. The agent list lives at `${OPENCLAW_HOME}/config/agents.map`. When searching from the CLI, use the agent's XDG wrapper:

```bash
# main agent
XDG_CONFIG_HOME=${OPENCLAW_HOME}/agents/main/qmd/xdg-config XDG_CACHE_HOME=${OPENCLAW_HOME}/agents/main/qmd/xdg-cache qmd query "..."
# dev agent and any other agent — same pattern, swap the agent name
```

### Main agent collections

| Collection | What's in it |
|---|---|
| `identity-main` | Core docs — SOUL, IDENTITY, TOOLS, AGENTS, NETWORK, MEMORY index |
| `wiki-main` | **Durable knowledge cortex.** Wiki — agent-behaviors (cross-agent rules), projects, tools, concepts, people. Primary durable memory home as of 2026-05-28. |
| `memory-main` | Daily memory files (YYYY-MM-DD.md) — 7-day capture layer that promotes content into `wiki-main` |
| `workspace-docs-main` | Full workspace markdown (reference, tasks, handoffs, learnings) |
| `skills-main` | Skill definitions (SKILL.md files) |
| `agents-*-identity` | Other agents' root identity/config docs (per-agent workspaces) |
| `agents-*-memory` | Other agents' daily memory files (per-agent workspaces) |
| `agents-*-wiki` | Other agents' durable wikis (per-agent workspaces) — the main agent can query specialist durable knowledge directly. |
| `handoffs-*` | Per-agent handoff files (main, dev, and any other agent) |

### Specialist collection hints

Collection names below are from each specialist agent's own QMD config. From the main agent, use the cross-agent equivalents (`agents-<agent>-wiki`, `agents-<agent>-memory`).

| What you're looking for | Agent | Key collections (within that agent) | From the main agent |
|---|---|---|---|
| Code projects, build configs, engineering decisions | dev | `projects-dev`, `identity-dev`, `wiki-dev` | `agents-dev-wiki`, `agents-dev-memory` |

## Context and collection scoping

QMD's `context:` metadata (set in `index.yml` or via `qmd context add`) improves search relevance by describing what each collection contains. It's returned alongside results.

Scope searches with `-c` when broad queries drift into the wrong corpus:

```bash
qmd search "standup notes this week" -c agents-dev-memory -n 10
qmd query "GenAI project status" -c wiki-main -c projects-dev -n 10
```

Omit `-c` to search everything.

## Diagnostics

```bash
qmd status     # collection counts and pending embeddings
qmd update     # re-index (use after adding/editing files in indexed paths)
qmd embed      # generate/rebuild vectors after update
```

If `qmd query` or `qmd vsearch` fails (model/GPU unavailable), fall back to `qmd search` with stronger lexical terms.

Note: older docs referenced `qmd doctor` — that subcommand is not present in the current CLI version. Use `qmd status` for health, and `qmd update`/`qmd embed` for repair.

## MCP tools

When using MCP (the default for OpenClaw agents), prefer structured queries:

```json
{
  "searches": [
    { "type": "lex", "query": "challenger crew status" },
    { "type": "vec", "query": "what is the current state of the challenger crew project" }
  ],
  "intent": "Find project status, not general concepts about crew.",
  "limit": 10
}
```

## Pitfalls

- **Do not stop at snippets.** Fetch documents before making claims.
- **Do not overuse semantic search.** If you know exact titles or terms, BM25 is faster and often better.
- **Do not mutate indexes casually.** `qmd collection add`, `qmd update`, and `qmd embed` change local state and can be expensive.
- **Model-backed commands can be environment-sensitive.** If `qmd query` or reranking fails, fall back to `qmd search` with stronger lexical terms.
- **Ambiguous user wording needs intent.** Add `intent:` rather than hoping query expansion guesses the right domain.
- **Collection names matter.** Scope with `-c` when the query could match multiple domains.
- **Recency:** QMD does not decay old results. For time-sensitive memory, check filenames — YYYY-MM-DD closer to today is more current.

## Setup and maintenance

Only run these when asked. Searching and retrieving are safe; index mutation is not casual.

```bash
qmd collection add ~/notes --name notes   # CLI alternative to editing index.yml
qmd context add qmd://notes "Description"  # CLI alternative to context: in index.yml
qmd update                                # re-index collections
qmd embed                                 # generate/rebuild vectors
qmd status                                # health check after changes
```