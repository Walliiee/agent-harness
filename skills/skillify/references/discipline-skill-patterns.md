# Discipline-skill patterns

Patterns for writing skills whose job is to enforce a rule, discipline, or
methodology — TDD, verification-before-completion, designing-before-coding,
anti-fabrication rules, etc. These skills must survive agent rationalization
under pressure.

Lifted from the (archived 2026-06-09) `writing-skills` skill; the keepers
distilled here, the TDD-for-docs and subagent-pressure-testing methodology
dropped because it doesn't match how this workspace actually iterates.

## 1. Description trap: "what" vs "when"

The description field is read first and most often. If it summarizes the
*workflow*, agents will follow the description and skip the skill body.

```yaml
# ❌ BAD: summarizes workflow — agents follow this and never read the skill
description: Use when executing plans — dispatches subagent per task with code review between tasks

# ❌ BAD: too much process detail
description: Use for TDD — write test first, watch it fail, write minimal code, refactor

# ✅ GOOD: triggering conditions only, no workflow summary
description: Use when executing implementation plans with independent tasks in the current session

# ✅ GOOD: symptoms + situations, no process leak
description: Use when tests have race conditions, timing dependencies, or pass/fail inconsistently
```

The verified failure case: a description saying "code review between tasks"
caused an agent to do ONE review, even though the skill's flowchart clearly
required TWO (spec compliance, then code quality). Changing the description
to "Use when executing implementation plans with independent tasks" — no
workflow summary — restored compliance.

**Rule of thumb:** the description tells the agent *whether to open the skill*.
Once opened, the skill body owns the workflow. Don't duplicate.

This complements skillify's section 1 (Description Quality) — same field,
different angle: skillify focuses on trigger coverage and token budget; this
focuses on the workflow-leak failure mode.

## 2. Rationalization table

Discipline skills get broken by smart agents finding loopholes. The fix is to
enumerate the loopholes explicitly. Build the table from observed violations
(yours or other agents'), not hypothetical ones.

```markdown
| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing about behavior under change. |
| "Tests after achieve the same goals" | Tests-after = "what does this do?" Tests-first = "what should this do?" |
| "It's about spirit, not ritual" | Violating the letter of the rules is violating the spirit. |
```

The table format works because it pre-empts the agent's own internal
monologue — the agent reads its own excuse spelled out before it has the
chance to make it. Each row is a small commitment device.

**When to build one:** any skill where the agent is supposed to *not do
something* under pressure (skip a step, take a shortcut, write before
checking). Pure how-to skills don't need this — they need examples and
flowcharts.

## 3. Red-flags list

Make self-checking trivially cheap. A short bullet list of "if you find
yourself thinking any of these, stop and restart" works better than a
paragraph of rules.

```markdown
## Red flags — STOP and start over

- Code before test
- "I already manually tested it"
- "Tests after achieve the same purpose"
- "It's about spirit, not ritual"
- "This case is different because..."

All of these mean: delete the code, start over with TDD.
```

The pattern: each bullet is short enough that an agent can match it against
its own state in one read. The bottom line removes the "what do I do now"
ambiguity.

## 4. Cross-skill references — no `@` links

Force-loading another skill via `@path/to/SKILL.md` burns ~200K context for
content the current task may never need.

```markdown
✅ GOOD: **REQUIRED BACKGROUND:** Use [[skillify]] before editing this skill
✅ GOOD: **REQUIRED SUB-SKILL:** superpowers:test-driven-development applies here
❌ BAD: @skills/testing/test-driven-development/SKILL.md
❌ BAD: See skills/testing/test-driven-development  (unclear if required)
```

Name the skill, mark its strength (REQUIRED / SUGGESTED / RELATED), let the
agent load it on demand if needed.

## 5. "Letter vs spirit" pre-emption

Cuts off an entire class of "I'm following the spirit" rationalizations:

```markdown
**Violating the letter of the rules is violating the spirit of the rules.**
```

Place this near the top of any rule-enforcement section. It works because
the agent will independently arrive at the spirit-vs-letter argument later;
naming it up-front removes the loophole.

## What was deliberately not lifted

The full TDD-for-docs methodology (RED-GREEN-REFACTOR via subagent pressure
scenarios) was not lifted. It's a valid practice, but in this workspace
skills are iterated by writing, smoke-testing, and fixing — not by
baselining against a subagent population first. If you ever want it back,
the original skill is in `${OPENCLAW_HOME}/workspace/cold-storage/`.

The `anthropic-best-practices.md` document was also archived alongside the
parent skill; if you want to cache Anthropic's official guidance locally,
pull it from cold-storage into this `references/` directory.

## Related

- [[skillify]] — the parent skill; this is its discipline-focused appendix
- [[adversarial-self-audit]] — same family of patterns at the agent-behavior
  level
- [[no-quick-fix-compound]] — discipline rule this whole approach exists to
  protect
