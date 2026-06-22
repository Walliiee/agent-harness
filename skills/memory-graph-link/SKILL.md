---
name: memory-graph-link
version: 1.0.0
description: Surface candidate [[slug]] backlinks for a new or freshly-edited wiki entry. Scans every other wiki .md across all configured workspaces for places mentioning the entry's slug/title that don't link yet, and reports suggested insertions.
triggers:
  - find backlinks
  - suggest wiki links
  - memory-graph-link
license: MIT
metadata: {"openclaw": {"emoji": "🔗"}}
---

# memory-graph-link — backlink candidate finder

When a new wiki entry lands, existing entries often already mention the same concept in prose — but without the `[[slug]]` link the gbrain graph layer relies on. This skill scans for those orphan mentions and reports them so the author (or a follow-up edit pass) can add proper links.

## When to use

- **Right after `wiki-write`** lands a new entry. Run on the new path; review suggestions; decide which existing entries to backlink-edit.
- **Quarterly graph audit** of high-traffic entries (proactively find stale orphan references that should now link).

## How to invoke

```bash
${OPENCLAW_HOME}/bin/memory-graph-link <path-to-entry.md> [--verbose] [--max-per-file N]
```

| Flag | Effect |
|---|---|
| (positional) | Path to the wiki entry. Required. |
| `--max-per-file N` | Cap suggestions per matched file (default 3) — avoids noise on long entries |
| `--verbose` / `-v` | Show derived search terms and skip-reasons |

## What it does

1. Read the target entry; extract slug (filename stem) and title (first `# ` line).
2. Compute search terms: slug + spaced-slug + title phrase + non-stopword title tokens longer than 4 chars (skipping tokens that are substrings of the slug).
3. Scan every `*.md` under `{workspace,workspace-*}/wiki/` for each agent in `${OPENCLAW_HOME}/config/agents.map` (excluding `INDEX.md` and the target itself).
4. For each candidate file:
   - Skip if it already contains `[[slug]]`.
   - Match search terms (longest first; phrase matches preferred).
   - Cap to `--max-per-file` per target.
5. Print a grouped report.

## Output

```text
[memory-graph-link] N candidate(s) across M file(s) for [[<slug>]]

  workspace/wiki/projects/foo.md
    L42  [<matched-term>]  <line preview…>
    → consider adding [[<slug>]] near these lines
```

## Exit codes

- `0` — clean run (may have found 0 or more suggestions)
- `2` — bad arguments / unreadable file

## When NOT to use

- Suggestions are advice, not auto-edits. Apply manually.
- Match is **lexical**, not semantic. For semantic backlink candidates (paraphrases without the exact slug), use `qmd query "<title>"` and review hits manually.
- Don't run on `INDEX.md` (it's an index — every entry "mentions" the wiki). The script skips this by default but a `--target=INDEX.md` invocation would be useless.

## Files

- Script: `${OPENCLAW_HOME}/bin/memory-graph-link` (Python, ~190 lines)
- This spec: `${OPENCLAW_HOME}/skills/memory-graph-link/SKILL.md`

## Related

- `wiki-write` — landing point for new entries; consider invoking memory-graph-link after wiki-write returns.
- `qmd` — semantic fallback when lexical match misses paraphrased mentions.
- `gbrain-query` — graph layer that benefits from the `[[slug]]` links this skill suggests.
