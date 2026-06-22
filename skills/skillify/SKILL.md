---
name: skillify
version: 2.1.0
description: >-
  Audit, improve, or create OpenClaw skills. Use for skill review, cleanup,
  creation, refactoring, trigger bugs, "why isn't this skill triggering",
  determinism fixes, or making new skills from scratch. Advisory by default;
  edits files only when asked.
license: MIT
compatibility: skills-ref optional; validate step degrades gracefully without it
metadata: {"openclaw": {"emoji": "🔬"}}
mutating: false
triggers:
  - skillify this
  - improve this skill
  - audit this skill
  - make this a skill
  - check skill completeness
  - why is this skill not triggering
  - skill not triggering
  - skill recognition
  - refactor skill
  - make skill deterministic
  - create a skill
  - new skill
---

# Skillify

Audit existing skills or create new ones. Advisory by default — read, analyze,
report. Edit files only when the user explicitly asks for implementation.

## Posture

- **Audit-only**: Read the skill, produce findings, recommend changes. Do not
  edit anything.
- **Implement**: Only when the user says to. Make the smallest scoped edits,
  verify them, and report what changed.

Never mutate skill files during an audit-only request.

## Pre-Audit

Before the manual checklist, run the measurement and validation scripts to
ground the audit in hard numbers:

```bash
{baseDir}/scripts/audit.sh <skill-dir>
```

This calls `measure.sh` and `validate-frontmatter.sh` automatically. Review
their output before starting the manual checklist.

If `skills-ref` is available, it also runs `skills-ref validate` for full spec
coverage.

## Audit Checklist

Run through these in order. Each section produces a finding: pass / needs work / missing.

### 1. Description Quality

The `description` field is the primary trigger mechanism.

- [ ] **Says what the skill does AND when to use it** — both required.
- [ ] **Includes realistic trigger phrases** — what the user would actually type.
  Include Danish variants if relevant.
- [ ] **Specific enough to avoid false triggers** — near-miss queries should not
  match.
- [ ] **Pushy enough** — skills undertrigger more than they overtrigger. Err
  toward broader matching. Example: instead of "Create LinkedIn posts", write
  "Orchestrate LinkedIn post creation. Use when: creating a post, drafting
  content, writing an opslag, any mention of LinkedIn..."
- [ ] **Under 200 characters** — OpenClaw injects descriptions into every system
  prompt. At 30 skills, a 400-char description burns ~12K tokens/turn. Target:
  100–200 chars. Max: 250. Run `{baseDir}/scripts/measure.sh <skill-dir>` for
  exact counts.
- [ ] **No XML tags** — `<example>` and similar tags are forbidden in
  descriptions by the Anthropic API surface and break frontmatter parsing.

**Trigger test**: Read the description and ask: "If the user typed [X], would
the agent reach for this skill?" Try 3 should-trigger and 2 should-not-trigger
prompts mentally.

### 2. Structure & Size

- [ ] **SKILL.md exists** with valid YAML frontmatter (name + description).
- [ ] **Under 500 lines** — if over, identify what can move to `references/`.
  Run `{baseDir}/scripts/measure.sh <skill-dir>` for line count.
- [ ] **Progressive disclosure** — three loading tiers:
  1. Metadata (name + description) — always in context, ~100 tokens.
  2. Instructions (SKILL.md body) — loaded on activation, keep under 500
     lines / 5000 tokens.
  3. Resources (references/, scripts/, assets/) — loaded on demand only.
- [ ] **No orphan files** — every file in the skill directory should be
  referenced from SKILL.md or a script.
- [ ] **File references one level deep** — `references/REFERENCE.md`, not
  `references/deep/nested/file.md`.

### 3. Instruction Clarity

- [ ] **Explanatory over imperative** — "why" beats "MUST". Explain reasoning
  so the model can generalize.
- [ ] **Examples included** — at least one worked example for the primary
  workflow.
- [ ] **Output format defined** — if the skill produces artifacts, the expected
  format should be explicit.
- [ ] **Edge cases addressed** — missing input, ambiguous input, out-of-scope
  input.

### 4. Determinism Separation

**Deterministic steps belong in scripts, judgment stays in SKILL.md.**

Deterministic (script candidates): validation checks, linting, formatting,
file creation from templates, data collection/aggregation, version bumps,
string replacements, git operations, build steps.

Non-deterministic (keep in SKILL.md): writing content, creative choices,
selecting approaches, interpreting ambiguous input, review judgments.

For each step, ask: "Would two runs produce the same output given the same
input?" If yes → script candidate.

**Script rules**: one script per responsibility, self-contained with clear error
messages, validate inputs, exit non-zero on failure, use relative paths from
skill directory, SKILL.md calls scripts explicitly — no hidden logic.

### 5. Trigger Conflict Detection

This is the most common source of skill routing failures. Two skills with
overlapping triggers cause the agent to either pick the wrong one or skip both.

**How to check:**

```bash
# Quick scan: extract all trigger phrases from all skill dirs and find duplicates
for f in ${OPENCLAW_HOME}/skills/*/SKILL.md ${OPENCLAW_HOME}/workspace/skills/*/SKILL.md \
         ${OPENCLAW_HOME}/workspace-*/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  dir=$(basename "$(dirname "$f")")
  awk '/^triggers:/,/^[a-z]/{if(/^[ ]*- /) print dir": "$0}' dir="$dir" "$f"
done | sed 's/^[ ]*- //' | sort | uniq -c | sort -rn | awk '$1 > 1'
```

If any trigger phrase appears in more than one skill, that's a conflict.

- [ ] **No exact trigger overlaps** — the same phrase in two skills' trigger
  lists means the agent cannot deterministically pick one. Either remove the
  duplicate, narrow it to the better owner, or reword one.
- [ ] **No near-miss conflicts** — similar triggers ("save memory" vs "save to
  memory") that could fire on the same user input. Differentiate with more
  specific phrasing ("save memory recall" vs "save session memory").
- [ ] **Scope boundary documented** — if two skills handle related but
  different aspects (e.g., gbrain query vs gbrain page writes), the triggers
  should make the distinction clear. Add "Use when" context to descriptions.

**Resolution patterns:**

| Conflict type | Fix |
|---|---|
| Exact duplicate trigger | Remove from the weaker owner, keep in the primary |
| Overlapping scope | Add scope qualifier to triggers ("gbrain query" vs "gbrain write page") |
| Ambiguous intent | Add "Use when" to description, reword triggers to be more specific |
| Merge candidate | If two skills do essentially the same thing, merge them |

### 6. Cross-Skill Coordination

- [ ] **No duplicate ownership** — if another skill does the same thing,
  document the routing boundary or merge them.
- [ ] **Pointers resolve** — every file path reference points to a real file.
- [ ] **Uses `{baseDir}`** for sibling references instead of hardcoded paths.
- [ ] **External dependencies noted** — tools, APIs, models the skill needs.

### 7. Spec Compliance

See `{baseDir}/references/spec-compliance.md` for the full spec reference.

For skills whose job is to enforce a rule, discipline, or methodology, see
`{baseDir}/references/discipline-skill-patterns.md` (description trap,
rationalization tables, red-flags lists, letter-vs-spirit pre-emption).

Required frontmatter:
- [ ] **`name`** — 1-64 chars, lowercase a-z/0-9/hyphens. Must match folder
  name. No `anthropic`/`claude` reserved words. No XML tags.
- [ ] **`description`** — 1-1024 chars (target: under 200). No XML tags.

Optional frontmatter:
- [ ] **`license`** — for public distribution.
- [ ] **`compatibility`** — max 500 chars, environment requirements.
- [ ] **`metadata`** — single-line JSON: `{"openclaw": {...}}`. Supports `emoji`,
  `homepage`, `os`, `skillKey`, `requires.bins`, `requires.env`,
  `requires.config`, `requires.anyBins`, `primaryEnv`, `install`, `always`.
- [ ] **`triggers`** — list of phrases that activate the skill.
- [ ] **`mutating`** — `true`/`false`, whether the skill modifies files.
- [ ] **`allowed-tools`** — space-separated pre-approved tools.

Run `{baseDir}/scripts/validate-frontmatter.sh <skill-dir>` for automated
checks.

## Audit Output Format

After running the checklist, produce:

```text
## Skill Audit: [skill-name]

### Summary
[1-2 sentence overall assessment]

### Findings
| Area | Status | Detail |
|------|--------|--------|
| Description | ✅/⚠️/❌ | [what's good or wrong] |
| Structure | ✅/⚠️/❌ | |
| Clarity | ✅/⚠️/❌ | |
| Determinism | ✅/⚠️/❌ | |
| Trigger Conflicts | ✅/⚠️/❌ | |
| Coordination | ✅/⚠️/❌ | |
| Spec Compliance | ✅/⚠️/❌ | |

### Recommended Changes
1. [Specific change with reasoning]
2. [...]

### Script Candidates
- scripts/[name] — [purpose, inputs, outputs]
```

Always show the full findings table before touching any files — the user may
want to accept only some changes.

## Creation Flow

When building a new skill rather than auditing:

1. **Confirm need** — is the workflow recurring or complex enough to deserve a
   skill? One-off tasks don't need skills.
2. **Check overlap** — run trigger conflict detection (section 5) against all
   existing skills. If your new skill shares triggers with an existing one,
   either narrow your triggers, reword them, or document why the overlap is
   intentional (different scope boundary).
3. **Pick owner** — which workspace owns this skill? Shared (main) or a
   per-agent workspace such as dev. See `${OPENCLAW_HOME}/config/agents.map`.
4. **Draft frontmatter first** — name and description are the most important
   lines. Description must include trigger phrases and "when to use" context.
5. **Draft SKILL.md body** — under 500 lines. Explanatory style, include
   examples, define output formats.
6. **Extract scripts** — run the determinism check (section 4) on every step.
   Extract script candidates before finalizing.
7. **Verify** — run `audit.sh` on the draft, check trigger overlap with
   existing skills, fix issues before presenting to the user.

## Gbrain Quality Gates

Use gbrain checks only when the skill is part of the gbrain ecosystem or the
user asks for that gate:

```bash
GBRAIN_HOME=$HOME gbrain skillify check <path> --json
GBRAIN_HOME=$HOME gbrain check-resolvable --json
```

Do not spend money on cross-model evals unless the user asked for it.

## Safety

- Do not mutate skill files during an audit-only request.
- Do not add broad "always use this" triggers.
- Do not create extra documentation files by default.
- Do not hide known gaps; put them in the audit or final note.
- When implementing, make the smallest scoped edits and verify them.

## Common Mistakes

| Mistake | Why It Fails | Fix |
|---------|-------------|-----|
| Description too vague | Skill never triggers | Add specific phrases and contexts |
| Description too narrow | Only triggers on exact wording | Add variants, Danish, casual phrasing |
| Giant SKILL.md (500+ lines) | Wastes context on every invocation | Move reference material to `references/` |
| Scripting judgment calls | Script outputs wrong answers confidently | Keep interpretation/creativity in SKILL.md |
| One mega-script | Hard to debug, hard to reuse | One script per responsibility |
| Silent script failures | Skill proceeds on bad state | Validate inputs, exit non-zero, print errors |
| Duplicating another skill's logic | Drift, inconsistency | Coordinate via references or merge |
| MUST/ALWAYS/NEVER overload | Model follows letter, misses spirit | Explain reasoning instead |
| No examples | Model guesses at output format | Include at least one worked example |
| Orphan files | Wasted disk, confusing for maintenance | Every file referenced from SKILL.md or deleted |
| Missing `metadata.openclaw` | Skill loads everywhere regardless of env | Add `requires.bins`/`requires.env` gating |
| `metadata` as YAML block | Silently ignored by strict parsers | Use single-line JSON: `{"openclaw": {...}}` |
| Not using `{baseDir}` | Relative paths break if CWD changes | Reference sibling files with `{baseDir}` |
| `name` contains reserved words | Violation on Anthropic API surface | Avoid `anthropic` and `claude` |
| XML tags in description | Forbidden, breaks frontmatter parsing | Remove all `<tag>` patterns |
| No `license` field | Unclear terms if distributing publicly | Add if publishing; safe to skip for private |
| Skipping validation | Frontmatter errors caught at runtime | Run `validate-frontmatter.sh` before shipping |
| Trigger overlap with another skill | Agent picks wrong skill or skips both | Deduplicate triggers, add scope qualifiers, or merge |