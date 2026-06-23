---
name: preflight
description: Run the agent-harness clone-level preflight doctor (deps, repo structure, an adapt.py dry-run) and summarize what is present vs missing, split into required / scheduler / optional. Invoke when the user wants to check whether a machine is ready to run agent-harness.
allowed-tools:
  - Bash
  - Read
---

# Preflight — is this machine ready for agent-harness?

Run the bundled clone-level doctor and summarize the result for the user. The
plugin's files are under `${CLAUDE_PLUGIN_ROOT}`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh"
```

Then report concisely:

- **Required** (template path / `adapt.py`): is it satisfied? If anything is
  missing here, the harness can't be adapted yet — call it out first.
- **Scheduler + DR tooling**: PyYAML, OS, `gh` — needed only to install/verify the
  macOS LaunchAgents and DR scripts.
- **Optional** (live memory stack: Postgres / Bun / QMD / Gbrain / Ollama /
  OpenClaw): note any that are missing or **below their tested baseline** (the
  script prints a warn-only line for those — surface it, but it is not a failure).

The script exits 0 when the required template path is ready and 1 if a required
dependency or repo file is missing — relay which case it is. To actually wire the
harness in, point the user at the `adapt` skill (`/agent-harness:adapt`).
