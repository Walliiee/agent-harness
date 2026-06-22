# Reference Example — Mixed-Item Capture

This is the canonical reference for how memory-capture should work.
Use this when in doubt about format or routing decisions.

The input below deliberately mixes several item types — a decision, a todo,
a tool reference, and a person — so the classify-and-route mechanics are
visible end to end.

---

## Input (what the user sent)

> "Decision: we standardize on the two-agent model — `main` orchestrates, `dev` does the building. Also remember to wire the nightly compact cron before Friday. The `memory-normalize` CLI is the deterministic stamper — use it instead of hand-editing daily logs. And note Alex Doe, the reviewer who owns the merge gate."

---

## Classification

| Item | Type | Target |
|---|---|---|
| Standardize on the two-agent model | Project decision | `workspace/wiki/projects/<slug>.md` via wiki-write (conf ≥ 0.85) + daily log |
| Wire the nightly compact cron before Friday | Actionable todo | `<current-workspace>/tasks/current.md` + daily log |
| `memory-normalize` is the deterministic stamper | Tool reference | `workspace/wiki/tools/<slug>.md` via wiki-write (conf ≥ 0.85) + daily log |
| Alex Doe — reviewer, owns merge gate | Person reference | `workspace/wiki/people/<slug>.md` via wiki-write (recurring entity) + daily log |

---

## Output (what was saved)

- ✅ `workspace/wiki/projects/two-agent-model-<date>.md` — decision written long-form via wiki-write; daily log gets a one-line pointer
- ✅ `workspace/wiki/tools/memory-normalize.md` — tool reference card via wiki-write; daily log gets a pointer
- ✅ `workspace/wiki/people/alex-doe.md` — person entry via wiki-write; daily log gets a pointer
- ✅ `<current-workspace>/tasks/current.md` — compact-cron todo added
- ✅ `memory/<date>.md` — daily log: pointers for the three promoted items + the todo, all stamped `<!-- mc:item -->`

---

## Confirm output format (what the agent said after saving)

```
Saved:
• Two-agent model decision → wiki/projects/ + daily log (pointer)
• Wire nightly compact cron → tasks/current.md + daily log
• memory-normalize stamper → wiki/tools/ + daily log (pointer)
• Alex Doe (reviewer) → wiki/people/ + daily log (pointer)

Nothing ambiguous. Nothing skipped.
```

---

## Domain-Specific Example (short)

If a deployment adds its own domain-specific routing rows (see the
"Domain-Specific Destinations" section of the routing table), the same
mechanics apply: classify the item, route it to the deployment's target
file, and always also write it to the current-workspace daily log.

**Input:** "Status: throughput benchmark passed at 2k req/s."

**Classification + routing:**

| Item | Type | Target |
|---|---|---|
| Throughput benchmark passed | Project decision / outcome | `workspace/wiki/projects/<slug>.md` + daily log |

**Confirm output:**

```
• Throughput benchmark passed → wiki/projects/ + daily log
```
