# Architecture

A debug-oriented map of the harness, layered foundation → self-improving loop.
Each layer answers three questions: **what is it**, **why does it exist**, and
**where does the code live**, so the next "why did X happen?" has a fast lookup.

Paths use `${OPENCLAW_HOME}` for the harness home directory (default
`~/.openclaw`) and `${GH_ORG}` for your GitHub org/owner. Both are filled in when
you run `scripts/adapt.py` (see [getting-started.md](getting-started.md)). Model
names and routing chains shown here are **examples only** — models are
account-specific and the harness assumes no particular provider.

---

## Layer 1 — Agents

You define your agents in `config/agents.map` (rendered from
`config/agents.map.template`). Each line is `<agent-id> <workspace-dir>
<persona-label>`. The default working set is two agents:

| Agent id | Role | Workspace | Example primary model |
|----------|------|-----------|-----------------------|
| `main` | Orchestrator / chief-of-staff | `${OPENCLAW_HOME}/workspace/` | (your choice) |
| `dev` | Code / build agent | `${OPENCLAW_HOME}/workspace-dev/` | (your choice) |

Add a row to grow — e.g. a `research` agent on `workspace-research`, an `ops`
agent on `workspace-ops`. `agents.map` is the single source of truth: the
scripts and schedulers read it instead of hardcoding agent ids, so adding or
renaming an agent is a one-file edit.

**Why multiple agents and not one:** each agent owns a content domain. The main
failure mode this prevents is *cross-agent contamination* — one agent's working
drafts polluting another agent's retrieval view and producing confident wrong
answers. The fix is to isolate workspaces and federate retrieval only where it
should bleed (see Layer 2).

**Model routing (EXAMPLE chains — models are account-specific):**

- **Daily / primary:** `model-a → model-b → model-c` (fall through on failure)
- **Subagent default:** `fast-model → cheaper-model → fallback` (e.g.
  `maxConcurrent 4`, depth 1, 900s timeout)
- **Coding subagents:** `code-model → code-fallback → general`
- **Per-agent overrides:** a learning or research agent might pin a single
  cheaper model; a heartbeat job might run an even cheaper model on a fixed
  interval.

These are illustrations of the *shape* of routing, not a recommendation. Which
model is right for which task is exactly the question the **model bakeoff**
(Layer 6b) answers with data. Whatever you choose is declared in your agent
config, not in the harness.

**Per-agent config** lives under `${OPENCLAW_HOME}/agents/<id>/` (agent prompts,
sandbox settings, skill allowlists).

---

## Layer 2 — Workspaces, repos, federation

Each workspace is **its own git repo** with a parallel layout:

```
workspace*/
  memory/        # daily files YYYY-MM-DD.md (hippocampus)
  wiki/          # durable knowledge cortex (concepts/projects/people/...)
  skills/        # agent-specific skills (override shared)
  cold-storage/  # historical pruned content
```

**Repo topology** — not a monorepo. Each workspace pushes to its own GitHub
remote under `${GH_ORG}` (one repo per workspace, plus one for the shared skills
bundle and one for the DR bundle in Layer 7). Keeping them separate means a
single workspace can be rebuilt, audited, or shared without dragging the others
along.

**Federation** (`${OPENCLAW_HOME}/config/gbrain-sources.json`) decides which
workspaces share a retrieval view. The policy is per-deployment: federate the
workspaces whose knowledge *should* cross-pollinate into the orchestrator's
query view, and isolate the ones that must not bleed (a private or
domain-specific agent often stays isolated with its own index). This is the
direct lever on the cross-contamination failure from Layer 1.

---

## Layer 3 — The memory store (4 tiers)

| Tier | What it is | Lives at | Updated by |
|------|-----------|----------|------------|
| **Daily memory** | 7-day capture window, hippocampus | `workspace*/memory/YYYY-MM-DD.md` | `memory-capture` skill at session-cleanup |
| **Wiki** | Durable cortex, canonical pages | `workspace*/wiki/{concepts,projects,people,...}/*.md` | `wiki-write` skill (†, see Layer 4) + `memory-promote` |
| **Graph store** ([Gbrain](https://github.com/garrytan/gbrain)) | Structured pages + typed graph + timeline (Postgres + pgvector) | config under `${OPENCLAW_HOME}`; DB on `localhost:5432`; MCP on a local port | hourly sync job |
| **Vector index** ([QMD](https://github.com/tobi/qmd)) | Fast local vector recall, per-agent indices + a hub view | `${OPENCLAW_HOME}/agents/<id>/qmd/`; MCP on a local port | sync job (every ~30 min) |

The harness ships wired to **[Gbrain](https://github.com/garrytan/gbrain)** (Garry
Tan) for the graph tier and **[QMD](https://github.com/tobi/qmd)** (Tobi Lütke) for
the vector tier — both fully local, both installed by `dr/bootstrap.sh`. They sit
behind the `memory-retrieve` interface, so either can be swapped for another
graph/vector backend without touching the skills above.

**Embedding alignment:** within any single index, all content must embed with the
**same model and dimensionality** — mixing embedding spaces silently breaks
similarity search inside that store. The shipped stack queries QMD and Gbrain
*separately* (QMD first, then Gbrain), so the two may use different embedders
(Gbrain via `bge-m3`; QMD via its own local GGUF model). You only need to align
them to each other if you ever merge their vectors into one shared space.

**Retrieval order rule:** query the **vector index first** (fast similarity),
then the **graph store** (structured pages + relationships). A single
`memory-retrieve` entry point enforces the order so callers don't have to
remember it.

**Promotion pipeline** (the consolidation path from hippocampus → cortex):

1. Conversation → `memory-capture` writes the daily file (stamped so only this
   skill may write daily memory).
2. **A few times a week** a `memory-promote` sweep materializes wiki pages from
   the recent daily captures.
3. **Daily** a `memory-compact` sweep collapses daily files older than the
   capture window into thin records (originals move to `memory/cold-storage/`).
4. **Hourly** the graph-store sync runs (it self-heals source config first, then
   syncs).
5. **Every ~30 min** the vector-index sync keeps indices in lockstep.

**Frontmatter contract** — every wiki page carries a canonical YAML block. A
small "quartet" of fields (type / title / tags) maps to dedicated columns, and
`name` + `description` carry retrieval rank. Three defenders keep it honest (see
Layer 6d): a structural validator at commit time, a retrieval audit at
write time, and a fleet-wide backfill on a daily sweep.

---

## Layer 4 — Skills (the verbs)

A **skill** is a self-contained `SKILL.md` plus an optional `bin/` runner.
**Schedulers invoke skills, not raw scripts.** The shared bundle lives in
`skills/` (pushed as its own repo); per-agent skills under `workspace*/skills/`
shadow the shared ones.

The table below maps the *roles* in the design. The **`skills/` directory is the
source of truth** for what actually ships — `ls skills/` is the canonical list.
Rows marked **†** describe a role in the broader live system that is **not in the
OSS bundle**: it's either site-specific (your gateway wiring) or a harness you
author yourself. The harness still ships the *gates* those roles depend on (e.g.
the frontmatter retrieval audit that a `wiki-write` skill would call).

| Skill | Purpose | Bundled |
|-------|---------|:-------:|
| `memory-capture` | Capture decisions/outcomes into daily memory (sole daily-memory writer) | ✓ |
| `memory-promote` / `memory-compact` | Promote 7-day captures → wiki; word-cap daily files | ✓ |
| `memory-retrieve` | Single retrieval entry point (vector index → graph store) | ✓ |
| `wiki-write` † | Authoritative wiki-entry writer (structural + retrieval audit gates) | — |
| `session-cleanup` † | Per-agent nightly close-out (write daily, reconcile tasks, sync, commit) | — |
| `morning-standup` / `evening-standup` / `brief` † | Trigger-driven (start of day, shutdown, meeting prep) | — |
| `drift-watcher` / `drift-learn` / `drift-ack` | Drift incident loop (Layer 6c) | ✓ |
| `freshness-watch` / `memory-bloat-audit` / `memory-capture-audit` | Self-improving watchers (Layer 6a) | ✓ |
| `model-bakeoff` † | Cross-model capability eval + weekly regression gate (Layer 6b) | — |
| `qmd-sync` / `wiki-lint` | Index sync; closed-graph link integrity | ✓ |

**Pattern rule:** *cron is a thin trigger; the skill does the work.* No business
logic in scheduler payloads — a payload is a one-line prompt that invokes a
skill. This is enforced by a `cron-wrapper-audit`.

---

## Layer 5 — Schedulers (two surfaces)

The harness uses two scheduler surfaces, intentionally separate. **Some jobs
appear on both** — when they do, the system-level definition is authoritative
and the agent-facing entry mirrors it. Confirm which surface owns a job before
editing it.

### 5a. Agent-facing crons (prompts that need a model)

Scheduled *prompts*, run by the gateway service. Each payload invokes a skill.
Typical entries:

| Cron | Schedule | Agent | What it does |
|------|----------|-------|--------------|
| Per-agent `session-cleanup` (staggered) | nightly | each | Write daily, reconcile, sync, commit |
| Memory dup check | nightly | each | Read-only compare today vs prior days |
| Memory compact | nightly | main | Collapse daily memory past the window |
| Daily ops digest | evening | main | Failed jobs + new lessons → notification channel |
| Index health check | morning | main | Vector-index liveness probe |
| Verify cron claims | morning | — | Independent check that artifact-producing crons actually produced |

### 5b. System daemons (no model needed)

OS-level scheduled jobs (on macOS, LaunchAgents under
`~/Library/LaunchAgents/`; the harness renders these from a single
`launchd/plist.template` + `jobs.yaml`). Most run through a wrapper that records
to a skill-runs ledger. DR copies live in the DR bundle (Layer 7).

- **Services (always-on):** the gateway, the vector-index MCP, the graph-store MCP.
- **Sync / index:** graph-store sync (hourly), vector-index sync (~30 min),
  workspace sync (several times a day), the DR walker (every few hours).
- **Memory pipeline:** memory-promote, memory-capture-audit, memory-bloat-audit,
  frontmatter-backfill.
- **Self-improvement:** drift-watcher (hourly), drift-analyzer, drift-liveness,
  drift-learn (weekly), freshness-watch (weekly), invariants-check (weekly),
  wiki-lint (weekly), model-bakeoff (weekly), cron-wrapper-audit (weekly),
  retrieval evals (a couple times a week).
- **DR / housekeeping:** DB backup (daily), backups push (weekly), skill-run
  reaping/archiving, session rotation.

**Why two surfaces:** agent-facing crons are prompts that need a model;
system daemons run without one. Mixing the two is a recurring source of flakes —
keep each payload on the surface that matches it.

---

## Layer 6 — The self-improvement loop

The system measures and heals itself across three sub-systems: **evals** (is
recall good?), the **model bakeoff** (which model for what?), and the **drift
loop** (autonomous detect → fix → learn). Plus the frontmatter/invariants
watchers that feed it.

### 6a. Evals — golden retrieval suite

- **Golden set:** a newline-delimited JSON file of query → expected-result
  entries, each with a `min_top_rank` threshold.
- **Runner:** measures top-1 retrieval hit vs the per-entry threshold. A
  pre-flight stale-slug audit hard-fails on a dead target before the run.
- **Schedule:** a couple of times a week; results land in a status file and a
  regression fires a drift incident.
- **Why:** retrieval quality silently rots as content moves or gets renamed. The
  eval is the canary.

### 6b. Model bakeoff — which model for what

*(The bakeoff harness is a role you author yourself — † in Layer 4, not in the
OSS bundle. The pattern is documented here because the routing in Layer 1 leans
on it.)*

- **Matrix:** a capability matrix of axes × models, scored cell by cell.
- **Regression gate:** diffs current verdicts against a baseline snapshot and
  fires a drift incident on any PASS→FAIL.
- **Schedule:** weekly. Built-in caveat: a lone weekly flip on a noisy axis
  (reasoning / long-context) means *re-run that cell*, not "regression confirmed."
- **Why:** the routing chains in Layer 1 are only as good as the evidence behind
  them. The matrix is the evidence; the gate stops a silent model-quality
  regression from poisoning your routing.

### 6c. Drift loop — autonomous fixing & debugging

Incidents are markdown files under `${OPENCLAW_HOME}/incidents/YYYY-MM-DD/`, with
a state machine **open → proposed → applied** (plus `undo`). The whole loop is
agent-driven through the skill wrapper.

1. **Detect (hourly):** a postmortem watcher scans daemon logs for failure
   signatures and opens incidents. Other emitters: freshness-watch,
   memory-bloat-audit, memory-capture-audit, cron-wrapper-audit, the source
   doctor.
2. **Analyze (every couple hours):** an analyzer classifies each open incident
   and proposes a typed fix (it must justify any premium model over the cheap
   default). A stale-target pre-check short-circuits dead-cron incidents to
   `obsolete`.
3. **Apply:** an apply step gates low-risk fixes automatically; a liveness guard
   runs periodically. Fixes are reversible (`undo`) with a corrective retry.
4. **Learn (weekly):** resolved incidents are compounded into durable rules.
5. **Verify:** a validator cross-checks composed drift messages against the
   underlying claims; a human acks via a `drift-ack`.

### 6d. Frontmatter / retrieval audits

| Check | Where | Catches |
|-------|-------|---------|
| Structural frontmatter validator | pre-commit hook | Missing fences, missing quartet, YAML parse errors |
| Retrieval audit (`--strict`) | `wiki-write` write step | Missing/short `description`, unquoted-colon hazard |
| Frontmatter backfill (`--apply`) | daily cron | Fleet-wide drift after agent edits |

Why three: the structural validator stays lenient on retrieval-critical fields
so it doesn't block writes; the retrieval audit fills that gap; the backfill
cron catches the rest.

### 6e. Weekly invariants check + source doctor

- **Invariants check** fingerprints every defense built so far and exits non-zero
  if any is missing — sync-hook tails, bin scripts present and executable, config
  files parseable, DR manifest URLs reachable, retrieval audit at zero failures.
  **Why:** any prior defense can be silently stripped by a future tool upgrade or
  `doctor --fix`. This is the meta-defense — the guard that guards the guards.
- **Source doctor** checks a declarative source manifest
  (`${OPENCLAW_HOME}/config/gbrain-sources.json`) against the live DB after every
  sync and auto-fixes path drift.
- **wiki-lint** enforces closed-graph link integrity within a single wiki: every
  internal link must resolve. (This OSS repo is *not* a closed wiki, so its own
  docs use plain prose and relative links instead.)

---

## Layer 7 — DR and backups

DR is one repo (pushed to `${GH_ORG}`) plus a walker that runs every few hours
and a periodic database push.

```
<dr-bundle>/
  bootstrap.sh               # idempotent bootstrap on a fresh machine
  restore-workspaces.sh      # clones every workspace + shared skills
  restore-gbrain.sh          # pulls latest DB dump + restores
  restore-qmd.sh             # restores vector-index state
  config/                    # sanitized operational config (templates, no secrets)
  cron/ + commitments/       # state snapshots (refreshed every few hours)
  launchd/                   # scheduler definition copies
  bin/ + tools/              # mirror of the walker + helpers
```

- **Walker:** commits and pushes each component on a fixed interval; presync
  hooks **sanitize** live config into a secret-free template, snapshot scheduler
  + commitment state, and mirror the walker itself (so a fresh-machine rebuild
  has a walker to bring everything back).
- **Database:** a daily backup plus a periodic push to a backups repo.
- **Fresh-machine restore:** `git clone <dr-bundle> && ./bootstrap.sh &&
  ./restore-workspaces.sh && ./restore-gbrain.sh && ./restore-qmd.sh`, then re-add
  API keys from the config template and re-load the schedulers.

---

## Debugging entry points

| Symptom | First place to look |
|---------|--------------------|
| Wrong answer that smells like cross-source bleed | Run the source doctor, then query the vector index for the bleed source |
| Agent-facing cron didn't fire | Cron list → status column; logs under `${OPENCLAW_HOME}/logs/` |
| System daemon didn't fire | The OS scheduler's last-exit for that job; stderr in `${OPENCLAW_HOME}/logs/` |
| Drift alert came in | `${OPENCLAW_HOME}/incidents/YYYY-MM-DD/` — read the incident, then `drift-ack` |
| Wiki page not retrievable | Run the retrieval audit on the file, then query the graph store for its title |
| Frontmatter regression after agent edits | Frontmatter backfill `--dry-run` then `--apply` |
| Weekly invariants failed | The invariants incident under `incidents/YYYY-MM-DD/` |
| Model quality regressed | Re-run the model bakeoff weekly job, then read the capability matrix |
| DR repo out of sync | The DR walker log |
| Verify a defense is wired | Read the invariants check — every fingerprint is named there |

---

## Related docs

- [getting-started.md](getting-started.md) — install + adapt walkthrough
- `config/agents.map.template` — declare your agents
- `examples/two-agent/` — a minimal `main` + `dev` worked example
- `scripts/adapt.py` — fit the templates to your project
- `scripts/scrub-audit.sh` — leak gate (no secrets/paths/personas ship)
