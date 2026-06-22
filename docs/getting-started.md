# Getting started

This walks you from a fresh clone to a running harness. There are two paths:
**ask your agent** (let Claude Code / Codex drive `scripts/adapt.py`) or **do it
manually**. They do the same thing — `adapt.py` just automates the placeholder
filling and validation.

Read [architecture.md](architecture.md) first if you want the why behind each
piece.

---

## 0. Prerequisites

- **Python 3.11+** (the adapt engine is pure stdlib — no `pip install` needed).
- **git** and a GitHub org/owner you can push to (this becomes `${GH_ORG}`).
- A harness home directory (default `~/.openclaw`, referred to as
  `${OPENCLAW_HOME}`).
- For the full memory stack: a local Postgres (graph store) and the vector-index
  service. These are optional for a first run — the memory skills degrade
  gracefully if the backends aren't up yet.

---

## 1. Clone

```bash
git clone https://github.com/${GH_ORG}/agent-harness.git
cd agent-harness
```

---

## 2. Adapt — fit the templates to your project

### Path A — ask your agent (recommended)

Open the repo in Claude Code or Codex and say:

> Run `scripts/adapt.py` to wire this harness into my project. My harness home is
> `~/.openclaw`, my GitHub org is `my-org`, and I want the default `main,dev`
> agents.

The agent will run `adapt.py`, which **probes** your machine for an existing
setup, **renders** the templates, **validates** the result, and shows you a diff
before anything is written. Review the diff, then tell it to re-run with
`--apply`.

### Path B — do it yourself

First, a dry run. `adapt.py` defaults to dry-run and writes nothing — it stages
the rendered files and prints a diff-style listing:

```bash
python3 scripts/adapt.py \
  --home ~/.openclaw \
  --gh-org my-org \
  --agents main,dev
```

`adapt.py` will also **probe** automatically: if it finds an existing
`~/.openclaw/openclaw.json`, `.claude/settings.json`, or a Codex config, it
infers `OPENCLAW_HOME` and any existing agent ids and uses them as defaults (your
flags still win). Run `python3 scripts/adapt.py --probe-only` to just see what it
detected.

When the staged output looks right, apply it:

```bash
python3 scripts/adapt.py \
  --home ~/.openclaw \
  --gh-org my-org \
  --agents main,dev \
  --apply --out ~/.openclaw
```

Optional Telegram (or any notification channel): pass `--telegram-chat-id
<id>` to fill the notification placeholder. Leave it off and the notification
steps stay inert.

---

## 3. Fill any remaining placeholders

`adapt.py` substitutes every `${VAR}` it knows about and then **validates** that
none are left unfilled. If validation reports leftovers, they are things only you
can decide. Edit the rendered files and re-run `--apply`. The variables in play:

| Variable | Meaning | Default |
|----------|---------|---------|
| `${OPENCLAW_HOME}` | Harness home directory | `~/.openclaw` |
| `${GH_ORG}` | GitHub org/owner for the per-workspace remotes | (required) |
| `agents.map` | Your agent roster (`<id> <workspace> <label>`) | `main`, `dev` |
| `${TELEGRAM_CHAT_ID}` | Notification channel id (optional) | unset → inert |

`agents.map` is the single source of truth for your agent roster — the scripts
and schedulers read it instead of hardcoding ids. See
`examples/two-agent/agents.map` for a filled-in example.

---

## 4. Install the schedulers

The harness ships **one** `launchd/plist.template` plus a `jobs.yaml` and an
installer that renders every scheduled job with your paths — nothing hardcoded.
After `adapt.py --apply` has written your config:

```bash
# Render + load the system daemons (macOS LaunchAgents):
bash launchd/install-launchagents.sh --home ~/.openclaw

# (On a fresh-machine rebuild, the DR bootstrap does this for you:)
./dr/bootstrap.sh --home ~/.openclaw --agents config/agents.map
```

The agent-facing crons (Layer 5a) are installed by your gateway from the rendered
config; the system daemons (Layer 5b) come from `launchd/`.

---

## 5. Verify

Two checks confirm the install is sound.

```bash
# 5a. DR / smoke test — confirms the bootstrap + restore wiring is intact:
bash dr/smoke-test.sh

# 5b. Leak gate — confirms no secrets/paths/personas leaked into anything you
#     edited (also runs in CI on every push/PR):
bash scripts/scrub-audit.sh
```

A green `scrub-audit` plus a passing `smoke-test` means the harness is wired
correctly and ships nothing personal.

You can also spot-check the live system:

- **Invariants:** run the weekly invariants check by hand once — it names every
  defense fingerprint and fails loudly if one is missing.
- **Retrieval:** write one wiki page via the `wiki-write` skill, then query it
  back through `memory-retrieve` (vector index first, then graph store).

---

## 6. Where to go next

- [architecture.md](architecture.md) — the 7-layer map and per-symptom debugging
  entry points.
- `skills/` — the skill bundles (the verbs). Read a `SKILL.md` to see what each
  does.
- `examples/two-agent/` — the minimal worked example to copy from.
