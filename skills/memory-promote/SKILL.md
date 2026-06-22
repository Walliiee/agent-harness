---
name: memory-promote
version: 1.0.0
description: Mon/Wed/Fri sweep that graduates carry-forward items from 7-day daily-memory window into durable wiki entries. Calls memory-canonicalize + wiki-write + brain-ops (for gbrain page registration). Cron-first; manual invocation supported.
license: MIT
metadata: {"openclaw": {"emoji": "🌾"}}
triggers:
  - promote memory
  - graduate to wiki
  - run promote sweep
  - consolidate daily memory
  - memory promotion
---

# memory-promote

Primary mode: **cron** (Mon/Wed/Fri 22:00 via launchd, wrapped by skill-wrapper). Manual invocation accepted for one-off catch-ups or backfill.

This skill is the bridge between the **hippocampus** (daily files, ephemeral, 7-day window) and the **cortex** (wiki, durable, indexed by both QMD and gbrain). Items that recur, get explicit-promote signals, or score high in classifier land in wiki. Lower-confidence items queue or stay daily. Stale items drop on the next compact.

**Out of scope:** writing new bullets to daily (`memory-capture`), reducing aged daily files to thin records (`memory-compact`), enforcing bloat invariants (`memory-bloat-audit`).

## 0. Start run telemetry

```bash
PARENT_ARG=""
if [ -n "${OPENCLAW_RUN_ID:-}" ]; then
  PARENT_ARG="--parent-run-id $OPENCLAW_RUN_ID"
fi
RUN_ID=$(${OPENCLAW_HOME}/bin/skill-run start \
  --skill memory-promote \
  --agent <current-agent> \
  --trigger <cron|interactive> \
  $PARENT_ARG)
export OPENCLAW_RUN_ID="$RUN_ID"
```

## 1. Discover candidate items

Scan all daily memory files inside the 7-day active window for **each agent** the sweep covers (default: all agents listed in `${OPENCLAW_HOME}/config/agents.map`, e.g. main, dev):

```bash
WINDOW_START=$(date -v-7d +%F)
for ws in workspace workspace-dev; do
  find "${OPENCLAW_HOME}/$ws/memory" -name "*.md" -newer /tmp/__cutoff 2>/dev/null
done
```

(Use `touch -t $(date -v-7d +%Y%m%d0000) /tmp/__cutoff` first.)

From each file:
- Parse `<!-- mc:item -->` lines (those are candidate units).
- Skip lines that are already pointers (start with `→ see [wiki/`) — those are graduated.
- Group by section (Decisions, Key Lessons, Carry Forward, What Happened, Quick Wins).

## 2. Score each candidate

Confidence score (0.0–1.0) is the sum of these signals, clipped to [0, 1]:

| Signal | Weight | Detection |
|---|---|---|
| Same-or-similar item appears in N ≥ 2 daily files | +0.30 per dup (cap +0.60) | Jaccard ≥ 0.7 on bullet body, ignoring dates |
| Section is `Decisions` or `Key Lessons` | +0.25 | Header lookup |
| Section is `Carry Forward` and recurred ≥ 3 days | +0.25 | Combine signals |
| Body contains a promotion verb: "decided", "principle", "rule", "always", "never", "lesson", "post-mortem", "rca" | +0.15 | Case-insensitive substring match |
| Body length ≥ 200 chars | +0.10 | Length proxy for substance |
| User explicit signal in trailing text: "[promote]", "(durable)", "ship to wiki" | +0.30 | Marker tokens |
| Body is a short todo ("call X", "ping Y", "check Z") | -0.30 | Strong negative — todos don't belong in wiki |
| Section is `What Happened` AND single-day | -0.20 | Activity log noise |

Final bucket:
- **≥ 0.85** → auto-promote
- **0.60–0.85** → queue
- **< 0.60** → drop (leave in daily; will compact or expire)

## 3. Auto-promote (≥ 0.85)

For each high-confidence cluster (a candidate plus any duplicates across days):

1. Call **`memory-canonicalize`** with: cluster body, proposed category (per `memory-capture/references/routing-table.md`), proposed slug. Receive verdict (`create-new` | `update` | `update-suggested`) and shaped markdown.
2. Call **`wiki-write`** with the canonical shape — lands in `workspace/wiki/<category>/<slug>.md` and updates `wiki/INDEX.md`. For `update` verdict, append to existing entry and refresh `_Last updated`.
3. Register a gbrain page so the durable entry is visible to gbrain queries:
   ```bash
   GBRAIN_HOME=$HOME gbrain sync --source workspace-main-wiki
   ```
   (Source ID matches the wiki being written. Main wiki = `workspace-main-wiki`; specialist wikis use `agents-<agent>-wiki`.)
4. **Replace the original daily-file bullet(s) with a pointer**:
   ```markdown
   - **[Title]** — promoted to wiki on YYYY-MM-DD → see [wiki/<category>/<slug>.md] <!-- mc:item -->
   ```
   Edit each daily file in place. Preserve the `<!-- mc:item -->` stamp.
5. **Trigger QMD re-index** so the new wiki entry is searchable immediately:
   ```bash
   ${OPENCLAW_HOME}/bin/qmd-sync --collections wiki-main,agents-<agent>-wiki
   ```
   (If `qmd-sync` doesn't exist yet, fall back to: `XDG_CONFIG_HOME=... qmd update && qmd embed`.)

## 4. Queue (0.60–0.85)

For each mid-confidence item, append to the per-agent promote queue:

```
${OPENCLAW_HOME}/<workspace>/memory/promote-queue.md
```

Entry format:
```markdown
## YYYY-MM-DD — <one-line summary> (score: 0.72)
- Source: <daily-file path>:<section>
- Proposed category: <category>
- Proposed slug: <kebab-case>
- Why queued: <signal explanation>
- Body:
  > <verbatim bullet body>
```

The user reviews the queue (or a future `memory-graph-link` skill surfaces it) and either flips the item to durable (forces ≥ 0.85 on next sweep with a `[promote]` marker) or leaves it to drop.

## 5. Drop (< 0.60)

No write. Item stays in daily file until `memory-compact` rolls the file over after 7 days.

## 6. End run telemetry

```bash
${OPENCLAW_HOME}/bin/skill-run end "$RUN_ID" \
  --outcome <success|partial|failure> \
  --task-completion <true|false> \
  --error-recovery true \
  --exit-code 0 \
  --completion-evidence "promoted: N, queued: M, dropped: K; wiki entries written: ...; gbrain sync: ok; qmd reindex: ok"
```

Outcome rubric:
- **success** — sweep completed for all covered workspaces, all auto-promotes landed in wiki AND gbrain AND QMD, queue updated, pointer-replacements in daily files succeeded.
- **partial** — one or more workspaces failed but others completed; or wiki write succeeded but gbrain/QMD sync failed (recoverable on next sweep).
- **failure** — total sweep aborted before any writes, OR wiki write succeeded but daily-file pointer replacement failed (leaves the duplicate the architecture forbids).

## Why this skill exists

Without promotion, daily files become a graveyard:
- Same item carried forward 14 days = 14 copies of the same text → bloat + rank inversion in gbrain.
- Long-form decisions stuck in daily logs → never indexed as durable knowledge → re-derived from scratch later.
- No flow from capture → curation → durable means the system can't compound.

memory-promote is the consolidation phase. Together with `memory-capture` (write), `memory-compact` (prune), `memory-bloat-audit` (enforce), and `memory-retrieve` (read), it forms a closed loop where memory actually compounds.

## Reference

- Architecture: cold-stored at `workspace/cold-storage/wiki-projects/memory-system-redesign.md`
- Shape helper: `${OPENCLAW_HOME}/skills/memory-canonicalize/SKILL.md`
- Wiki writer: `workspace/skills/wiki-write/SKILL.md`
- gbrain page registration: `${OPENCLAW_HOME}/skills/brain-ops/SKILL.md`
- QMD reindex: `${OPENCLAW_HOME}/skills/qmd/SKILL.md`
- Per-agent routing: `${OPENCLAW_HOME}/skills/memory-capture/references/routing-table.md`
