# agent-harness

A drop-in **self-improving memory + operations harness** for AI agents. It gives
any agent setup — [OpenClaw](https://github.com/), Hermes, or a plain
Claude Code / Codex project — four things that are normally hand-rolled and
fragile:

1. **Layered memory** — a daily capture file → durable wiki → indexed recall
   (vector + graph), with a promotion pipeline that graduates what lasts and
   compacts what doesn't.
2. **A self-improvement loop** — drift incidents (detect → analyze → apply →
   learn), retrieval evals, and weekly invariant checks that catch your own
   defenses being silently stripped by an upgrade.
3. **Disaster recovery** — one-command bootstrap + restore from a sanitized,
   secret-free template of your config.
4. **Operational hygiene** — frontmatter contracts, freshness/rot watchers,
   closed-graph wiki linting, and a thin-trigger cron pattern.

It ships as **templates + scripts**. Nothing here contains anyone's data,
secrets, or machine paths — you (or your agent) fit it to your project on install.

> **Status:** v1, template-repo distribution. A Claude Code plugin and an
> `npx skills add` skill wrap the same `scripts/adapt.py` in a later pass.

---

## Quick start

```bash
git clone https://github.com/${GH_ORG}/agent-harness.git
cd agent-harness

# Option A — let your agent fit it to your project (recommended):
#   open this repo in Claude Code or Codex and say:
#   "Run scripts/adapt.py to wire this harness into <my project>."

# Option B — do it yourself:
./dr/bootstrap.sh --home ~/.openclaw --agents config/agents.map.template
```

`adapt.py` **probes** your target (config files, agent names, workspace paths),
**renders** the templates with your values, **validates** the result, and shows
you a diff before writing anything.

---

## What's in here

| Path | What it is |
|------|------------|
| `bin/` | The harness scripts, grouped by job (`memory/`, `drift/`, `freshness/`, `frontmatter/`, `invariants/`, `index/`, `observability/`, `dr/`). |
| `skills/` | Agent skills (SKILL.md bundles) for the verbs — memory-capture, memory-promote, drift loop, wiki-lint, etc. |
| `config/` | Templates: `openclaw.json.template`, `agents.map.template`, `gbrain-sources.json.template`. |
| `launchd/` | One `plist.template` + `jobs.yaml` + an installer that renders all schedulers — no hardcoded paths. |
| `dr/` | Bootstrap + restore scripts, `workspaces.manifest.yaml.template`, `secrets/README.md`. |
| `docs/` | `architecture.md` (the full design), `getting-started.md`, per-subsystem guides. |
| `examples/two-agent/` | A minimal `main` + `dev` setup you can clone and run. |
| `scripts/adapt.py` | The "fit it to your project" engine. |
| `scripts/scrub-audit.sh` | Leak gate — fails if any author identifier/secret/path appears. Runs in CI. |

See **[docs/architecture.md](docs/architecture.md)** for how the layers fit
together, and **[docs/getting-started.md](docs/getting-started.md)** to install.

---

## Design principles

- **Cron is a thin trigger; the skill does the work.** No business logic in
  schedulers.
- **Every defense is fingerprinted.** A weekly invariants check fails loudly
  when a future upgrade strips a guard.
- **No secrets, ever.** Config ships as a template; `scrub-audit.sh` enforces it.
- **Bring your own models.** Routing chains are examples — models are
  account-specific; the harness doesn't assume any provider.

## License

MIT — see [LICENSE](LICENSE).
