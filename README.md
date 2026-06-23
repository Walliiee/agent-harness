# agent-harness

**A drop-in memory, self-healing, and disaster-recovery harness for AI agents.**

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![CI: scrub-audit](https://img.shields.io/badge/CI-scrub--audit-brightgreen.svg)
![Python 3.11+](https://img.shields.io/badge/python-3.11%2B-blue.svg)
![Status: v1](https://img.shields.io/badge/status-v1-orange.svg)

Most agent setups remember nothing between sessions, silently rot when an
upgrade strips a guard, and can't be rebuilt when the machine dies. `agent-harness`
gives any agent stack — [OpenClaw](https://github.com/), Hermes, or a plain
Claude Code / Codex project — the four pieces that are normally hand-rolled,
fragile, and personal-to-your-machine:

> **Layered memory** that graduates what lasts · **a self-improvement loop** that
> detects and fixes its own drift · **one-command disaster recovery** · and the
> **operational hygiene** to keep all three honest.

It ships as **templates + scripts with zero personal data**. A leak gate
(`scrub-audit`) runs in CI and fails the build if a single secret, absolute path,
or author identifier ever sneaks in. You — or your agent — fit it to your project
on install with one Python script.

---

## Why this exists

Every serious agent project eventually rebuilds the same scaffolding:

| The pain | What the harness gives you |
|----------|----------------------------|
| Agents forget everything between sessions | A **4-tier memory store** (daily → wiki → graph → vector) with a promotion pipeline |
| A tool upgrade silently strips a guard you built | A **weekly invariants check** that fingerprints every defense and fails loudly |
| Retrieval quietly rots as pages move or get renamed | **Golden retrieval evals** that fire a drift incident on regression |
| Something breaks at 3am and nobody notices for days | A **drift loop** that detects → analyzes → fixes → learns, autonomously |
| The laptop dies and the agent is gone | **`bootstrap.sh`** rebuilds the whole stack from git in one command |
| Cross-agent content bleeds into the wrong answers | **Workspace isolation + federation** you control per-deployment |

None of this is novel on its own. The value is that it's *wired together,
fingerprinted, and recoverable* — and that it ships clean enough to publish.

---

## The shape of it

```
                    ┌──────────────────────────────────────────────┐
  Layer 1  Agents   │  main (orchestrator)   dev (builder)   …     │  agents.map
                    └──────────────────────────────────────────────┘
  Layer 2  Repos    │  workspace/   workspace-dev/   … (one git repo each)
                    │  └ federation decides which share a retrieval view
                    ├──────────────────────────────────────────────┤
  Layer 3  Memory   │  daily file ─promote→ wiki ─sync→ graph store
                    │       (hippocampus)  (cortex)    + vector index
                    ├──────────────────────────────────────────────┤
  Layer 4  Skills   │  the verbs: memory-capture, memory-promote,
                    │  drift-watcher, wiki-lint, qmd-sync, …
                    ├──────────────────────────────────────────────┤
  Layer 5  Cron     │  5a agent-facing prompts  ·  5b system daemons
                    ├──────────────────────────────────────────────┤
  Layer 6  Loop     │  evals · model bakeoff · drift (detect→fix→learn)
                    │         · frontmatter/invariants watchers
                    ├──────────────────────────────────────────────┤
  Layer 7  DR       │  bootstrap + restore + sanitized config template
                    └──────────────────────────────────────────────┘
```

Each layer is documented — what it is, why it exists, and where the code lives —
in **[docs/architecture.md](docs/architecture.md)**, organized so the next
"why did *X* happen?" has a fast lookup.

---

## The stack it installs

The harness is provider-agnostic at the interface, but it ships **wired for a
specific, proven, fully-local stack** — so a fresh install is real storage with
memory, not a pile of TODOs:

| Tier | Tool | What it does |
|------|------|--------------|
| **Graph store** (durable cortex) | **[Gbrain](https://github.com/garrytan/gbrain)** by [Garry Tan](https://github.com/garrytan) | Markdown-first, Postgres-backed knowledge layer that auto-wires a *typed* knowledge graph (`works_at`, `founded`, `attended`, …) over your notes — hybrid vector + BM25 + RRF search, zero LLM calls for graph extraction. |
| **Vector index** (fast recall) | **[QMD](https://github.com/tobi/qmd)** by [Tobi Lütke](https://github.com/tobi) | On-device search engine — BM25 + vector + local LLM rerank via `node-llama-cpp`, all offline. The low-latency path, queried first. |

`dr/bootstrap.sh` installs both (`@tobilu/qmd` + a Bun-linked `gbrain`), pulls the
embedding model, and brings the MCP services up. Both sit behind the single
`memory-retrieve` interface (**QMD first, then Gbrain**), so the skills don't care
which backend answers — and you can swap either for another vector/graph store
without touching them. Out of the box, though, it's a complete
**storage + memory + eval + self-check** install.

---

## Quick start

> **This is a template repository — not a packaged plugin (yet).** There is no
> one-command plugin installer; you clone (or **“Use this template”**) and run
> `adapt.py` to fit it to your machine. A Claude Code plugin / `npx` wrapper is on
> the [roadmap](#status--roadmap). Platform support varies — the full live stack is
> macOS-oriented; see [Platform support](#platform-support).

**Use it as a template** (the recommended path): click **“Use this template”** on
the repo, or clone it:

```bash
git clone https://github.com/${GH_ORG}/agent-harness.git
cd agent-harness
```

Then fit the templates to your project. Two ways — same engine:

**Option A — let your agent drive it (recommended).** Open the repo in Claude Code
or Codex and say:

> Run `scripts/adapt.py` to wire this harness into my project. Home is
> `~/.openclaw`, GitHub org is `my-org`, agents `main,dev`.

**Option B — run it yourself.** `adapt.py` is pure-stdlib Python and defaults to a
safe dry-run that writes nothing:

```bash
# 0. Check this machine: deps, repo structure, an adapt.py dry-run (writes nothing)
bash scripts/preflight.sh

# 1. Dry-run: probe your machine, render the templates, validate, print a diff
python3 scripts/adapt.py --home ~/.openclaw --gh-org my-org --agents main,dev

# 2. Looks right? Apply it
python3 scripts/adapt.py --home ~/.openclaw --gh-org my-org --agents main,dev \
  --apply --out ~/.openclaw

# 3. Install the schedulers (macOS), then verify
bash launchd/install-launchagents.sh --home ~/.openclaw   # macOS LaunchAgents
bash scripts/scrub-audit.sh  # nothing personal leaked (also runs in CI)
bash dr/smoke-test.sh        # live-stack health — only meaningful AFTER full bootstrap
```

`adapt.py` **probes** your target (config files, agent names, workspace paths),
**renders** the templates with your values, **validates** that no placeholder or
leak remains, and shows you exactly what it staged before writing anything.

Full walkthrough: **[docs/getting-started.md](docs/getting-started.md)**.

---

## What's in here

| Path | What it is |
|------|------------|
| `bin/` | The harness scripts, grouped by job: `memory/`, `drift/`, `freshness/`, `frontmatter/`, `invariants/`, `index/`, `observability/`, `dr/`. |
| `skills/` | The bundled agent skills (`SKILL.md` + optional `bin/`) — memory-capture, memory-promote, drift loop, wiki-lint, qmd-sync, and more. `ls skills/` is the canonical list. |
| `config/` | Templates: `openclaw.json.template`, `agents.map.template`, `gbrain-sources.json.template`, plus a `config-README.md`. |
| `launchd/` | One `plist.template` + `jobs.yaml` + an installer that renders every scheduler — no hardcoded paths. |
| `dr/` | `bootstrap.sh` + `restore-*.sh`, `workspaces.manifest.yaml.template`, `smoke-test.sh`, `secrets/README.md`. |
| `docs/` | `architecture.md` (the full design), `getting-started.md`, `disaster-recovery.md`. |
| `examples/two-agent/` | A minimal `main` + `dev` setup — the shape of what `adapt.py` produces. |
| `scripts/adapt.py` | The "fit it to your project" engine. |
| `scripts/scrub-audit.sh` | The leak gate — fails if any identifier/secret/path appears. Runs in CI. |

---

## How it keeps itself honest

Two ideas do most of the work, and they're the reason this is publishable:

**1. Every defense is fingerprinted.** A weekly `invariants-check` walks every
guard built so far — sync-hook tails present, bin scripts executable, config
parseable, DR URLs reachable, retrieval audit at zero failures — and exits
non-zero the moment one goes missing. This is the meta-defense: *the guard that
guards the guards.* A future `doctor --fix` or tool upgrade can't silently
strip your hardening without the check screaming.

**2. No secrets, ever — enforced, not promised.** `scrub-audit.sh` greps every
tracked file for secret-shaped values and fails CI if it finds one. Your own
identifiers (home path, handle, domain, persona names) live in a gitignored
local denylist (`scripts/.scrub-denylist`, from the tracked `.example`), so the
gate can catch them on your machine without the list of literals itself ever
shipping. On the live side, a config sanitizer
redacts anything whose key contains `token`, `secret`, `api_key`, `password`,
`credential`, or `authorization` (as substrings — bare `token` included) before
config is ever pushed to a DR repo. Templates keep their `${VAR}` bindings;
the values never leave your machine.

Other principles the codebase holds to:

- **Cron is a thin trigger; the skill does the work.** No business logic in
  scheduler payloads — a payload is a one-line prompt that invokes a skill,
  enforced by `cron-wrapper-audit`.
- **Bring your own models.** Routing chains in the docs are *example shapes* —
  models are account-specific and the harness assumes no provider. The
  model-bakeoff pattern is how you pick with data instead of vibes.
- **One source of truth for your roster.** `agents.map` declares your agents;
  scripts and schedulers read it instead of hardcoding ids. Adding an agent is a
  one-line edit.

---

## Requirements

- **Python 3.9+** — `adapt.py` is pure stdlib, no `pip install`.
- **git** + a GitHub org/owner you can push to.
- **PyYAML** (`pip3 install pyyaml`) — only for the scheduler installer and the DR
  restore/smoke tooling (they parse `jobs.yaml` and the workspace manifest).
  `adapt.py` does **not** need it.
- For the full memory stack: a local Postgres (for [Gbrain](https://github.com/garrytan/gbrain),
  the graph store) and [QMD](https://github.com/tobi/qmd) (the vector index) —
  both installed by `dr/bootstrap.sh`. They're **optional for a first run**; the
  memory skills degrade gracefully if the backends aren't up yet.

Run **`bash scripts/preflight.sh`** on any machine to see exactly what's present
and what's missing, split into required / scheduler / optional.

### Platform support

| Capability | macOS | Linux | Windows |
|---|:--:|:--:|:--:|
| `adapt.py` render + apply (the template path) | ✅ | ✅ | ✅¹ |
| Bundled skills copied/rendered | ✅ | ✅ | ✅¹ |
| `scrub-audit` / `preflight` | ✅ | ✅ | ✅¹ |
| Scheduler install (`launchd`) | ✅ | ❌² | ❌² |
| `dr/bootstrap.sh` full bootstrap | ✅ | ❌² | ❌ |
| Full Gbrain/QMD live stack | ✅ | ⚠️ manual | ❌ |

¹ Untested but pure Python/bash — use WSL or Git-Bash on Windows.
² The scheduler ships as macOS **LaunchAgents**; on Linux you'd port `launchd/jobs.yaml`
to systemd timers or cron yourself. The memory, skills, drift, and self-improvement
layers are OS-agnostic — only the scheduler and DR bootstrap are macOS-specific.

---

## Security & trust boundary

This harness runs **autonomous local agents** that read and write your filesystem
and execute the bundled scripts on a schedule. That's the point — but it's also a
real trust boundary, so install it deliberately:

- **Treat it like code you run, not a sandbox.** Agents inherit the permissions of
  the user running the LaunchAgents. Run it as your normal user, never root.
- **Review before you schedule.** Read `launchd/jobs.yaml` — you install exactly
  those jobs and nothing else runs that isn't declared there.
- **Secrets stay in `${VAR}` env bindings,** never in tracked files. `scrub-audit`
  (CI) blocks identifier/secret leaks and the config sanitizer redacts
  secret-shaped keys before any DR push. Real values live only in your gitignored
  `openclaw.json`.
- **Full filesystem/exec access is the current default,** because the harness is
  built for a single-user local machine. Adapting it for a shared or less-trusted
  host means scoping down the per-agent skill allowlists (`config/agents.map` +
  per-agent configs) first. A locked-down default profile is a roadmap item, not
  today's default — so this is an opt-in-to-broad-trust tool, by design.

---

## Status & roadmap

**v1 — template-repo distribution.** Stable, in daily use, scrub-audit green.

Next pass (tracked, not yet shipped):

- A **Claude Code plugin** wrapping `scripts/adapt.py` for one-command install.
- An **`npx skills add`** skill so the bundle installs into any agent project
  without cloning.

Some roles the architecture describes (`wiki-write`, `session-cleanup`,
standups, `model-bakeoff`) are part of the broader live system and are **not in
the OSS bundle** — they're site-specific or a harness you author yourself. The
harness ships the *gates* they depend on. `docs/architecture.md` marks these
clearly (†) so the map never over-promises the bundle.

---

## Documentation

- **[docs/architecture.md](docs/architecture.md)** — the 7-layer map + a
  per-symptom debugging table.
- **[docs/getting-started.md](docs/getting-started.md)** — clone → adapt →
  install → verify.
- **[docs/disaster-recovery.md](docs/disaster-recovery.md)** — fresh-machine
  rebuild runbook.
- **[examples/two-agent/](examples/two-agent/)** — the minimal worked example.

---

## Acknowledgements

This harness is an operational layer *around* two excellent open-source projects,
and ships configured to use them out of the box — if you build on it, go star
theirs:

- **[Gbrain](https://github.com/garrytan/gbrain)** by **[Garry Tan](https://github.com/garrytan)**
  — the self-wiring, Postgres-backed knowledge graph that serves as the memory
  store's graph tier (MIT).
- **[QMD](https://github.com/tobi/qmd)** by **[Tobi Lütke](https://github.com/tobi)**
  — the fast, fully-local markdown search engine that serves as the vector
  recall tier.

The layered-memory, drift-loop, and disaster-recovery patterns here are the
harness; Gbrain and QMD are the storage and recall it's wired to.

---

## License

MIT — see [LICENSE](LICENSE). Contributions welcome under the same terms.
```