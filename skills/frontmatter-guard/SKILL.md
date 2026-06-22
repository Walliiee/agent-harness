---
name: frontmatter-guard
version: 1.0.0
description: "Audit and carefully repair YAML frontmatter issues reported by gbrain. Use for frontmatter audit, brain lint, malformed YAML, missing delimiters, nested quotes, or gbrain doctor frontmatter warnings."
license: MIT
metadata: {"openclaw": {"emoji": "🧾"}}
triggers:
  - frontmatter audit
  - validate frontmatter
  - check frontmatter
  - fix frontmatter
  - brain lint
  - malformed yaml
  - gbrain doctor frontmatter
---

# Frontmatter Guard

Use this skill to inspect and repair Markdown/YAML frontmatter issues surfaced
by `gbrain doctor` or `gbrain frontmatter`. It is conservative by default:
audit first, classify second, and only mutate after the exact target set is
clear.

## Environment

Always target the real gbrain home:

```bash
GBRAIN_HOME=$HOME gbrain frontmatter ...
```

Do not run bare gbrain commands from Codex/OpenClaw synthetic HOME.

## Default Flow

1. Run the read-only audit:

   ```bash
   GBRAIN_HOME=$HOME gbrain frontmatter audit --json
   ```

2. Summarize counts by source and error code. Do not paste raw JSON unless asked.
3. Separate structural noise from real corruption:
   - `MISSING_OPEN` on normal root/reference Markdown can be acceptable.
   - `EMPTY_FRONTMATTER`, `YAML_PARSE`, `NESTED_QUOTES`, `NULL_BYTES`, and
     `MISSING_CLOSE` are stronger repair candidates.
4. For one path or a small reviewed set, validate before fixing:

   ```bash
   GBRAIN_HOME=$HOME gbrain frontmatter validate <path> --json
   ```

5. Preview fixes before writing:

   ```bash
   GBRAIN_HOME=$HOME gbrain frontmatter validate <path> --fix --dry-run
   ```

6. Apply `--fix` only after the user has approved the target path/set, or when the
   requested task explicitly authorizes repair for those files.

## Fix Policy

- `NULL_BYTES`, `MISSING_CLOSE`, `NESTED_QUOTES`, `SLUG_MISMATCH`: usually
  mechanical; still preview first.
- `YAML_PARSE`: inspect before fixing; causes vary.
- `MISSING_OPEN`: do not auto-fix globally. Many Markdown files are
  intentionally plain documents, not gbrain entity pages.
- `EMPTY_FRONTMATTER`: do not auto-fix without reading the file.

`gbrain frontmatter validate --fix` writes `.bak` files. Treat those backups as
expected safety artifacts; do not delete them unless asked.

## Canonical-shape check (OpenClaw-specific)

`gbrain frontmatter validate` only checks YAML structural integrity. It does
NOT enforce OpenClaw's canonical wiki/* frontmatter shape.

Canonical shape: **flat top-level**, gbrain quartet first (`type`/`title`/`tags`
— what gbrain extracts to dedicated columns per `gbrain/src/core/markdown.ts:96-99`),
then Claude/QMD hooks (`name`/`description`), then dates/source. NO `metadata:`
nesting.

Use `bin/check-canonical-shape.py` (sibling script) to enforce:

```bash
# Scan all OpenClaw wiki/* dirs across workspaces
${OPENCLAW_HOME}/skills/frontmatter-guard/bin/check-canonical-shape.py --wiki --summary

# Scan one path
${OPENCLAW_HOME}/skills/frontmatter-guard/bin/check-canonical-shape.py ${OPENCLAW_HOME}/workspace/wiki

# Machine-readable for cron / weekly check-invariants
${OPENCLAW_HOME}/skills/frontmatter-guard/bin/check-canonical-shape.py --wiki --json
```

Error codes emitted:

| Code | Meaning | Fix |
|---|---|---|
| `CANONICAL_MISSING_TYPE` | No top-level `type:` — gbrain can't extract to `pages.type` | Add top-level `type:` matching the folder (e.g. `wiki/people/` → `type: person`) |
| `CANONICAL_MISSING_TITLE` | No top-level `title:` — gbrain falls back to humanized filename | Add top-level `title:` matching the body H1 |
| `CANONICAL_METADATA_NESTING` | `metadata:` block contains `type` or `title` (legacy Option A shape) | Promote nested fields to top-level, delete `metadata:` block |
| `CANONICAL_SLUG_MISMATCH` | `name:` doesn't equal filename stem | Set `name:` to the kebab-case filename (no `.md`) |
| `CANONICAL_EXPLICIT_SLUG` | Has explicit `slug:` (creates SLUG_MISMATCH trap) | Remove `slug:` — gbrain auto-derives via `inferSlug(filePath)` |

Repair pattern for a single file: read it, identify which fields are nested or
missing, rewrite the frontmatter block keeping body unchanged. The transform
script at `bin/canonicalize-wiki-frontmatter.py` (sibling) is the reusable
batch fixer — point its `WIKI_ROOT` at the target dir (default is
`workspace/wiki/`), it walks all `.md` files and rewrites frontmatter to the
canonical hybrid shape while preserving body content. Used 2026-06-11 to
transform 99 main-workspace wiki files.

## Scope Guidance

Prefer source-scoped or directory-scoped work:

```bash
GBRAIN_HOME=$HOME gbrain frontmatter audit --source learn --json
GBRAIN_HOME=$HOME gbrain frontmatter validate ${OPENCLAW_HOME}/workspace/wiki --json
```

Avoid full-workspace repair runs. The current workspace intentionally contains
many plain Markdown control files.

## Report Format

```text
Frontmatter audit: <total> issue(s)
Top repair candidates: <codes/counts>
Likely acceptable/noise: <codes/counts>
Recommended next path: <path or source>
No files changed.
```

After a fix:

```text
Fixed: <n> file(s)
Backups: <n> .bak file(s)
Verified: <command/result>
Remaining: <summary>
```
