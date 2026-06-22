---
name: wiki-lint
version: 1.0.0
description: "Graph/link/synthesis-integrity linter for the OpenClaw wikis. Finds dangling [[links]] (the pages-worth-writing backlog), orphan pages, duplicate slugs, and INDEX drift across the workspace wikis. Use for wiki health, wiki lint, dead links, orphan pages, index drift, what should I write next."
license: MIT
metadata: {"openclaw": {"emoji": "🔗"}}
triggers:
  - wiki lint
  - wiki health
  - lint the wiki
  - dead links
  - dangling links
  - orphan pages
  - index drift
  - what should I write next
---

# Wiki Lint

The cross-page integrity check for the wikis. It fills the one gap the existing
hygiene layer leaves open — none of these look *between* pages:

| Existing | Scope |
|---|---|
| `freshness-watch` | mtime/lifespan pruning (wiki/* is `evergreen`, so untouched) |
| `frontmatter-guard` | per-file YAML structure + canonical shape |
| `openclaw-invariants-check` | per-script DR defense fingerprints |
| **`wiki-lint`** | **the connective tissue: links, orphans, duplicate slugs, index drift** |

This is the integrity layer that rots as the wiki grows — the thing humans
abandon wikis for not maintaining. The LLM does it on a timer instead.

## What it checks (deterministic, no LLM)

- **`DANGLING_LINK`** — `[[target]]` with no page anywhere. Grouped by target and
  ranked by inbound count = **the "pages worth writing" backlog**. A target 5
  pages already link to is a high-value page to write next.
- **`ORPHAN`** — page with 0 inbound `[[links]]` and not listed in any `INDEX.md`.
  Candidate to cross-link or cold-store.
- **`DUPLICATE_SLUG`** — two pages resolving to the same slug → `[[link]]`
  ambiguity. Tagged **intra-wiki** (same workspace = real ambiguity, the
  highest-severity finding) vs **cross-wiki** (same slug in two workspaces =
  only ambiguous if those wikis are federated; isolated namespaces are fine).
- **`INDEX_MISSING` / `INDEX_DEAD`** — page on disk absent from its category
  `INDEX.md`, or an `INDEX.md` entry pointing at a deleted file. Keeps the
  hand-maintained index honest.
- **`STALE_REVIEW`** — orphan whose `updated:` is older than `--stale-days`
  (default 365). Wiki pages are `evergreen` by policy, so this is a **review**
  flag, never a prune.

Two deliberate design choices:
- Link resolution is **global across all scanned roots** and normalises `_`→`-`
  + case, so federation cross-refs and slug drift don't fire false danglings.
- Links are parsed **straight from markdown, not gbrain's graph** — gbrain
  typed-edge resolution has known bugs (#1846 bare-name, #1847 empty link_type).
  Markdown is the source of truth.
- `[[links]]` inside fenced/inline **code blocks are ignored** — the template
  examples in the `WIKI.md` operating manuals are illustrations, not edges.

## Run it

```bash
SKILL=${OPENCLAW_HOME}/skills/wiki-lint/bin/wiki-lint.py

$SKILL --wiki                 # all configured workspace wikis, full report
$SKILL --wiki --summary       # one-line counts (what the weekly cron logs)
$SKILL --wiki --json          # machine-readable
$SKILL ${OPENCLAW_HOME}/workspace/wiki   # one wiki only
$SKILL --wiki --stale-days 180      # tighter staleness bar
$SKILL --wiki --summary --no-fail   # cron/ledger mode: exit 0 on findings (exit 2 = real error)
$SKILL --wiki --fix --dry-run       # preview BROKEN_REF auto-repoints ([[prefix-slug]] → [[slug]])
$SKILL --wiki --fix                 # apply them (only where the de-prefixed page exists)
$SKILL --check path/to/page.md      # write-path guard: only this file's danglings (exit 1 if any)
$SKILL --wiki --demote a-slug,b-slug --dry-run   # preview cold/generic [[X]] → backtick downgrades (drop --dry-run to apply)
```

**`--fix`** touches only the BROKEN_REF class — a memory-prefixed `[[link]]` whose
de-prefixed slug is a real page. WRITE_PAGE, DEMOTE, MERGE, orphans, and duplicate
slugs are never auto-touched; they need judgment. **`--check <file>`** is what
`wiki-write` runs before declaring a page done — it resolves against all wiki roots
but reports only the danglings *that file* introduces (and exits 2 if the path isn't a scanned wiki page, so it never silently false-passes). **`--demote <slugs>`** downgrades an explicit comma-separated list of dangling `[[X]]` to backtick `` `X` `` — the cold/generic class, by slug, never inferred.

Read-only. It never mutates a page. Exit 0 = clean, 1 = findings (normal — a
living wiki always has a backlog), 2 = invocation error.

## Report format

```
wiki-lint: <N> finding(s) across <R> root(s), <P> pages

▸ DANGLING_LINK — pages worth writing (Tt targets, Rr refs)
    owner-graph-schema      ← 4 ref(s)  projects/atlas-*.md, …
▸ DUPLICATE_SLUG — [[link]] ambiguity (n)
▸ ORPHAN — no inbound links, not in any INDEX (n)
▸ INDEX drift — missing:a dead:b
▸ STALE_REVIEW — orphan + aged (review, not prune) (n)

Top action: <single highest-value next move>
No files changed.
```

Surface only the tiers that have findings. Lead with `DUPLICATE_SLUG` (a bug),
then the high-ref dangling targets (highest-leverage pages to write).

## Optional LLM passes (on demand — NOT in the weekly cron)

The deterministic pass is the cheap 80%. Two judgement checks cost tokens, so run
them only when acting on a report, never on the timer:

1. **Contradiction candidates.** For a suspect page, `qmd query` its title +
   description; the top 3–5 hits are its semantic neighbours. For each near pair,
   ask: *"Do these two pages assert contradictory claims? Quote the conflicting
   lines or answer NONE."* Only near pairs reach the LLM — qmd does the pruning.
2. **Concept gaps.** Mostly already free: the ranked `DANGLING_LINK` backlog
   *is* the concept-gap list. The LLM's job is only to judge which high-ref
   targets are worth a page now vs. a passing mention.

## How findings close (ties to the broader wiki plan)

- Writing a high-ref dangling target removes it from the backlog **and** drops
  the orphan count next run (the new page links outward).
- **File explorations back** (the conversation-synthesis capture idea): when a
  session produces a real synthesis, drop it in `concepts/` — that page resolves
  dangling links and earns inbound edges, so wiki-lint scores it as healthy
  rather than orphaned. The linter is the feedback loop that rewards capturing.

## Conservative policy

- Never auto-delete or auto-edit. Orphans and stale pages are *candidates* for
  the user's KEEP/TRIM/MERGE/COLD judgement, not automatic action.
- `DUPLICATE_SLUG` is the only finding worth interrupting for — it breaks links
  silently. Everything else is a backlog the user drains on their cadence.

## Cron wiring

Thin trigger → `~/Library/LaunchAgents/ai.openclaw.wiki-lint.plist`, Sun 05:15
(after invariants + freshness at 05:00), routed through `skill-wrapper` so runs
land in the skill-runs ledger. The cron runs `--summary --no-fail` — findings
still print but it exits 0, so a normal run records as *success* in the ledger
(only a real linter error, exit 2, logs as failure). It appends the one-line
trend weekly to `${OPENCLAW_HOME}/logs/wiki-lint.log`; the full report is on-demand
via this skill.

**v2 hooks (not built yet, deliberately):** a `--report-dir` flag to archive
dated JSON, and proactive alerting that diffs against last week and pings Drift
only when a *new* duplicate slug appears or the dangling count jumps. Build after
a few weeks of baseline — don't pre-wire alerts for an unproven signal.
