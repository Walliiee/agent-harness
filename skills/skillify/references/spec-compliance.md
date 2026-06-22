# Spec Compliance Reference

Full AgentSkills spec and OpenClaw extension details for skill audits.

## Required Frontmatter

- **`name`** — 1-64 chars, lowercase a-z, numbers, hyphens. No leading/trailing
  hyphen, no consecutive hyphens. Must match folder name. Anthropic API surface
  additionally forbids XML tags and the reserved words `anthropic` and `claude`.

## Optional Frontmatter

- **`license`** — License name or reference to a bundled license file. Add when
  distributing publicly; safe to omit for private skills.

- **`compatibility`** — Max 500 chars. Human-readable environment requirements
  (runtime, packages, network, etc.). Not used for runtime gating — use
  `metadata.openclaw.requires.*` for that.

- **`metadata`** — Per agentskills.io spec: a YAML map of string keys to values.
  For OpenClaw specifically: must be **single-line JSON**
  (`{"openclaw": {...}}`); YAML block syntax works with standard YAML parsers
  but may silently fail in OpenClaw's strict parser. For OpenClaw, use
  `metadata.openclaw` with:
  - `emoji` — for the macOS Skills UI.
  - `homepage` — URL shown in UI. (Also valid as top-level `homepage` field.)
  - `os` — platform gate: array of `"darwin"`, `"linux"`, `"win32"`.
  - `skillKey` — overrides which config key is used for lookup.
  - `requires.bins` — all must exist on PATH.
  - `requires.env` — env vars that must be set.
  - `requires.config` — `openclaw.json` paths that must be truthy.
  - `requires.anyBins` — at least one must exist on PATH.
  - `primaryEnv` — ties to `skills.entries.<name>.apiKey`.
  - `install` — installer specs (brew/node/go/uv/download) for the UI.
  - `always: true` — skip all gates, always include.

- **`allowed-tools`** — Confirmed agentskills.io spec field. Space-separated
  pre-approved tools. Example: `Bash(git:*) Bash(jq:*) Read`. Experimental —
  support varies by runtime.

## OpenClaw-Specific Extensions

- **`user-invocable`** — `false` hides it from slash commands.
- **`disable-model-invocation`** — `true` keeps instructions out of the agent
  prompt (still invocable as slash command).
- **`command-dispatch: tool`** + `command-tool` + `command-arg-mode` — for
  direct tool dispatch.

## Loading Precedence (highest wins on name conflict)

1. `<workspace>/skills`
2. `<workspace>/.agents/skills`
3. `~/.agents/skills`
4. `~/.openclaw/skills`
5. Bundled skills
6. `skills.load.extraDirs` (from openclaw.json)

When debugging "wrong skill version loading," check which source level is
winning.

## Per-Skill Config Overrides (`openclaw.json` → `skills.entries.<name>`)

- `enabled: false` — disable the skill entirely
- `apiKey` — string or SecretRef; injected via `primaryEnv`
- `env` — key-value pairs injected only if not already set in process env
- `config` — arbitrary per-skill fields for skills that read their own config
- `allowBundled` — allowlist for bundled skills only