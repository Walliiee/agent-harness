# Example: two-agent setup (`main` + `dev`)

The minimal working harness: one orchestrator and one developer agent. This is
exactly what `scripts/adapt.py` produces for the default roster, shown here so
you can see the shape of the result before running anything.

## The roster

[`agents.map`](agents.map) declares the two agents:

```
main   workspace       Orchestrator
dev    workspace-dev   Developer
```

`agents.map` is the single source of truth for your roster — the scripts and
schedulers read it instead of hardcoding ids. To grow, add a row (e.g.
`research   workspace-research   Researcher`) and re-run `adapt.py`.

## Resulting layout

After `adapt.py --apply` against a home of `~/.openclaw`, you get:

```
${OPENCLAW_HOME}/
  openclaw.json              # rendered from config/openclaw.json.template
  config/
    agents.map               # this file, copied/rendered into place
    gbrain-sources.json      # which workspaces share a retrieval view
  agents/
    main/                    # per-agent prompts, sandbox, skill allowlist
    dev/
  workspace/                 # main's workspace (its own git repo)
    memory/  wiki/  skills/  cold-storage/
  workspace-dev/             # dev's workspace (its own git repo)
    memory/  wiki/  skills/  cold-storage/
  incidents/  logs/  skill-runs/   # runtime state (gitignored)
```

Each `workspace*/` is its own git repo pushing to a remote under your
`${GH_ORG}`. The shared `skills/` bundle and the DR bundle are separate repos
too — see [../../docs/architecture.md](../../docs/architecture.md) Layer 2 and
Layer 7.

## The config it renders from

The agent definitions, model routing, and gateway settings come from
[`../../config/openclaw.json.template`](../../config/openclaw.json.template)
(model routing there is illustrative — models are account-specific). This
example only shows the roster; it does not duplicate the templates or scripts.

## Try it (dry run)

```bash
# From the repo root:
python3 scripts/adapt.py --home ~/.openclaw --gh-org my-org --agents main,dev
```

That stages the rendered files and prints a diff-style listing without touching
your real setup. Add `--apply --out ~/.openclaw` when it looks right. Full
walkthrough: [../../docs/getting-started.md](../../docs/getting-started.md).
