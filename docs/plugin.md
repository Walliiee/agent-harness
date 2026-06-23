# Claude Code plugin

The repo doubles as a **Claude Code plugin** that wraps `scripts/adapt.py` behind
two slash commands, so installing the harness into a project is a guided flow
instead of a manual script run. The plugin is a thin convenience layer — it adds
no capability the CLI path doesn't already have (`docs/getting-started.md`).

> The plugin is **inert until installed**. A bare checkout of this repo does not
> auto-load anything into Claude Code — the `.claude-plugin/` manifest and
> `plugin/skills/` only activate after `/plugin install` (or a one-off
> `claude --plugin-dir`). Nothing here changes a project you've merely cloned.

## What it ships

The repo is both a plugin and its own single-plugin marketplace:

- `.claude-plugin/plugin.json` — the plugin manifest. `skills` is pointed at
  `plugin/skills/` so **only** the two wrapper skills load — the repo's
  OpenClaw `skills/` bundle is *not* pulled into Claude Code.
- `.claude-plugin/marketplace.json` — lists this repo as a marketplace with one
  plugin (`source: "./"`).
- `plugin/skills/adapt/` — `/agent-harness:adapt`: probe → dry-run → confirm →
  apply, driving `scripts/adapt.py`. Manual-invoke only (it won't auto-fire), and
  it never writes without an explicit confirmation.
- `plugin/skills/preflight/` — `/agent-harness:preflight`: runs the clone-level
  dependency doctor and summarizes required / scheduler / optional.

## Install

```text
/plugin marketplace add ${GH_ORG}/agent-harness
/plugin install agent-harness@agent-harness
```

(The marketplace name and the plugin name are both `agent-harness`, hence
`agent-harness@agent-harness`.) Replace `${GH_ORG}` with the org/owner you cloned
or forked into.

### Try it without installing

```bash
claude --plugin-dir /path/to/agent-harness
```

This loads the plugin for that session only — useful to test before adding the
marketplace.

## Use

```text
/agent-harness:preflight
```

Checks the machine and reports what's ready vs missing.

```text
/agent-harness:adapt --home ~/.openclaw --gh-org my-org --agents main,dev
```

Drives the full adapt flow. It runs preflight, probes your machine, does a
**dry-run that writes nothing**, shows you the staged diff, and **applies only
after you explicitly approve**. Omit any argument and it will ask rather than
guess.

## Relationship to the CLI path

Everything the plugin does, you can do by hand — see
[getting-started.md](getting-started.md). The plugin just sequences
`preflight.sh` → `adapt.py --probe-only` → dry-run → `--apply` with a
confirmation gate, so you don't have to remember the order or the flags.
