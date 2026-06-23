# Hardening — scoping an agent down for a shared or less-trusted host

The shipped default is **deliberately permissive**: the harness is built for a
single-user local machine, where the agents are *you*, automated. Out of the box
each agent gets broad filesystem and exec access because that's what makes the
memory loop, DR scripts, and self-healing actually work without friction.

That default is the wrong one the moment the machine is **shared, multi-tenant,
or otherwise less-trusted**. This guide is the opt-in path to scope an agent
down. It does **not** change the default — you apply it per agent, deliberately,
to the agents that need it.

> **TL;DR:** copy the overrides from
> [`../config/hardened-profile.example.json`](../config/hardened-profile.example.json)
> into a per-agent block in `openclaw.json`, narrowing fs + exec + the skills
> allowlist. Re-run `bash scripts/scrub-audit.sh` (nothing here ships secrets)
> and restart the gateway.

---

## The trust surface — what actually grants capability

Five knobs decide what an agent can do. The permissive default and the hardened
value for each:

| Knob (per-agent, under `agents.list[].tools`) | Default (permissive) | Hardened | What it gates |
|---|---|---|---|
| `fs.workspaceOnly` | `false` | **`true`** | Whether file reads/writes are confined to the agent's workspace dir, or can touch the whole filesystem. |
| `exec.security` | `"full"` | **`"deny"`** | Whether the agent can run shell commands at all. `"full"` = unrestricted; `"deny"` = no exec tool. |
| `exec.applyPatch.workspaceOnly` | `false` | **`true`** | Whether code-patch edits are confined to the workspace. |
| `alsoAllow` | includes `sessions_spawn`, `subagents` | **drop both** | Whether the agent can spawn sub-sessions / subagents (fan-out = a larger blast radius). |
| `skills` | broad roster (github, tavily, browser, …) | **minimal core** | Every skill is a capability. The fewer an agent carries, the smaller its reach. |

There are two more global gates already set the safe way in the shipped template,
so the hardened profile relies on them rather than restating them:

- **`tools.exec.security: "deny"`** at the top level (the *global* default is
  already no-exec; per-agent blocks are what open it up). Hardening simply
  *stops overriding* it for the agent.
- **`approvals.exec.enabled: true`** — exec approvals are on globally.

---

## Why `exec: "deny"` doesn't break the memory loop

The instinct is "if the agent can't run shell, the memory pipeline stops." It
doesn't — because **the pipeline's scripts run as scheduled daemons, not through
the agent's exec tool.** The hourly graph-store sync, the ~30-min vector sync,
memory-promote, the backfill, the invariants check — all of those are
LaunchAgents (Layer 5b in [architecture.md](architecture.md)), running the
`bin/` scripts directly under your user. The agent denied exec still gets a fully
working memory loop; it just can't *itself* shell out. That's the capability you
most want to remove on a shared host, and it's the cheapest to give up.

The skills an agent needs to *participate* in memory (capture, retrieve, promote,
write wiki) are tool-level skills, not shell — so they keep working under
`exec: "deny"`.

If a specific hardened agent genuinely needs to run a command, prefer leaving
`exec.security: "deny"` and triggering the work through a daemon or a narrowly
scoped skill, rather than re-opening full exec.

---

## Applying it — per agent

In `openclaw.json`, find the agent's block in `agents.list`. A permissive block
looks like this (trimmed):

```jsonc
{
  "id": "research",
  "tools": {
    "fs":   { "workspaceOnly": false },
    "exec": { "security": "full", "ask": "off",
              "applyPatch": { "workspaceOnly": false } },
    "alsoAllow": ["sessions_list", "sessions_send", "sessions_spawn",
                  "sessions_yield", "subagents"]
  },
  "skills": ["qmd", "memory-retrieve", "gbrain-query", "github", "tavily",
             "browser-automation", "dispatching-parallel-agents", "..."]
}
```

Replace the `tools` and `skills` keys with the hardened versions from
[`../config/hardened-profile.example.json`](../config/hardened-profile.example.json):

```jsonc
{
  "id": "research",
  "tools": {
    "fs":   { "workspaceOnly": true },
    "exec": { "security": "deny", "ask": "off",
              "applyPatch": { "workspaceOnly": true } },
    "alsoAllow": ["sessions_list", "sessions_send", "sessions_yield"]
  },
  "skills": ["memory-capture", "memory-retrieve", "memory-promote",
             "qmd", "wiki-write", "frontmatter-guard", "drift-ack"]
}
```

Then add back, one at a time, only the skills that agent demonstrably needs —
each one is a deliberate widening, not a default.

---

## Verify

```bash
# Config still parses + nothing secret leaked into anything you edited:
bash scripts/scrub-audit.sh

# If the live stack is up, let OpenClaw validate the edited config:
openclaw doctor --fix       # only if no ${VAR} placeholders remain

# Restart so the new per-agent scoping takes effect:
openclaw gateway restart
```

A hardened agent should: still answer and retrieve memory; still receive its
scheduled daemon-driven syncs; and **fail closed** if you ask it to read outside
its workspace or run a shell command.

---

## What this is *not*

- **Not a sandbox.** Scoping the tool allowlist reduces reach; it is not an OS
  jail. For real isolation, run the agent's gateway as a dedicated, unprivileged
  user (or in a container) — the harness still assumes it runs as a normal user,
  never root. See the *Security & trust boundary* section in the
  [README](../README.md#security--trust-boundary).
- **Not the default, by design.** Flipping the shipped default to locked-down
  would break the single-user local experience the harness is built for. This
  stays opt-in so the common case stays frictionless and the hardened case stays
  explicit.
