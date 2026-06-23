---
name: adapt
description: Wire the agent-harness templates into the current project by driving scripts/adapt.py — probe the machine, render the templates from the user's home/org/agents, validate, show a diff, and apply only after explicit confirmation. Invoke when the user wants to install or set up agent-harness.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
---

# Adapt the agent-harness to this project

You are wiring the `agent-harness` templates into the user's setup using the
bundled `scripts/adapt.py`. The plugin's files are under `${CLAUDE_PLUGIN_ROOT}`.

**Hard rule: never write to a real home directory without an explicit, separate
confirmation from the user.** `adapt.py` defaults to a dry-run that writes
nothing — keep it that way until the user has seen the diff and said go.

## Inputs

Parse `$ARGUMENTS` for these, and **ask for any that are missing** (do not guess):

- `--home` — the harness home dir (commonly `~/.openclaw`).
- `--gh-org` — the GitHub org/owner for the per-workspace remotes.
- `--agents` — comma-separated roster (default `main,dev` if the user has no
  preference).
- `--telegram-chat-id` — optional notification channel id; omit if not given.

## Steps

1. **Preflight first.** Run the clone-level check and summarize anything missing:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh"
   ```

   If a REQUIRED dependency is missing, stop and tell the user — do not proceed
   to apply.

2. **Probe** the machine so the user sees what was auto-detected:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/adapt.py" --probe-only
   ```

3. **Dry-run** (writes nothing) with the resolved inputs, and show the user the
   staged diff verbatim:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/adapt.py" \
     --home <home> --gh-org <org> --agents <roster>
   ```

4. **Confirm.** Ask the user to review the diff and explicitly approve writing.
   Do not continue without a clear yes.

5. **Apply** only after approval:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/adapt.py" \
     --home <home> --gh-org <org> --agents <roster> --apply --out <home>
   ```

6. **Verify**: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/scrub-audit.sh"` and report
   the result. Point the user at `docs/getting-started.md` for installing the
   schedulers and the live-stack steps.

If `adapt.py` reports leftover `${VAR}` placeholders after apply, surface them —
those are values only the user can decide. Never invent secret values.
