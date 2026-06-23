# Disaster Recovery — OpenClaw agent-harness stack

This runbook restores the full OpenClaw stack onto a fresh macOS machine using
the contents of this repo plus your `gbrain-backups` repo.

**Estimated wall-clock:** most of the time is the QMD model download + embedding
pass; you can walk away during it.

---

## Prerequisites on the fresh machine

1. macOS (any recent version).
2. Xcode Command Line Tools — `xcode-select --install` if not already present.
3. Apple ID signed in (for App Store-installed apps you want back; not strictly
   required for the stack itself).
4. A GitHub Personal Access Token with `repo` scope — you'll paste this into
   `gh auth login` during step 1. Re-issue from https://github.com/settings/tokens
   if you don't have the old one.

Two environment variables drive the templated paths and URLs:

```sh
export OPENCLAW_HOME="$HOME/.openclaw"   # install root (defaults to $HOME/.openclaw)
export GH_ORG="<your-github-org>"        # org/user that owns your workspace repos
```

---

## Sequence (do each step in order)

### Step 0 — Clone this repo

```sh
cd ~
git clone https://github.com/${GH_ORG}/agent-harness.git
cd agent-harness
chmod +x dr/*.sh launchd/install-launchagents.sh
```

If you don't have `git` yet, install Xcode Command Line Tools first
(`xcode-select --install`).

### Step 1 — Run bootstrap

```sh
./dr/bootstrap.sh
```

This is idempotent and safe to re-run. It will:

- Install Homebrew if missing.
- Install brew formulae: `postgresql@17`, `node`, `gh`, `jq`, `ollama`.
- Start the postgres and ollama services.
- Install `bun` (the TypeScript runtime gbrain needs).
- Pull the `bge-m3` ollama model (1.2 GB — gbrain's embedding model).
- Install global npm packages: `openclaw`, `@tobilu/qmd`, `@openai/codex`, `clawpatch`.
- Create system directories under `~/.openclaw/` and `~/.gbrain/`.
- Create QMD XDG dirs and add the `qmd` alias to `~/.zshrc`.
- Run `gh auth login` (interactive — paste your PAT).
- Clone all workspaces per `dr/workspaces.manifest.yaml.template` (via
  `restore-workspaces.sh`).
- Run `bun install && bun link` inside `~/gbrain/` so the `gbrain` CLI is on PATH.
- Deploy any bundled `bin/` and `gbrain/` scripts back to their live paths.
- Render the sanitized `openclaw.json.template` to `~/.openclaw/openclaw.json`
  (expanding `${OPENCLAW_HOME}`).
- Install + load LaunchAgents (via `launchd/install-launchagents.sh`).
- Run `openclaw doctor --fix` (only if no `${VAR}` placeholders remain).

**Open a new terminal after bootstrap** so the `qmd` alias and bun PATH load.

### Step 2 — Fill in secrets

Open `~/.openclaw/openclaw.json` and replace every remaining `${VAR}`
placeholder with the real value. The full enumeration with re-issue URLs is in
[`../dr/secrets/README.md`](../dr/secrets/README.md). Restore order matters:

1. `${ANTHROPIC_API_KEY}`, `${GEMINI_API_KEY}`, `${TAVILY_API_KEY}`,
   `${BRAVE_API_KEY}` — re-issue from each provider's dashboard.
2. `${GITHUB_PERSONAL_ACCESS_TOKEN}` — same token you used for `gh auth login`
   (needs `repo` + `read:org`).
3. `${GBRAIN_TOKEN_*}` — leave as placeholders for now; auto-minted in step 4.
4. `${HARNESS_TG_CHAT_ID}` — your Telegram owner/chat ID.
5. `${OPENAI_CODEX_PROFILE_ID}`, `${OPENAI_CODEX_EMAIL}` — re-run `openclaw auth`
   after the rest of the stack is up.

Also re-create the local secrets file at the path referenced by
`secrets.providers.local.path`. Its contents are the `TELEGRAM_TOKEN_*` and
`GATEWAY_AUTH_TOKEN` values per the table in `dr/secrets/README.md`.

After editing, validate:

```sh
openclaw doctor --fix
```

### Step 3 — Restore gbrain database

```sh
./dr/restore-gbrain.sh
```

This locates `postgresql@17`, creates the `gbrain` role if missing, picks the
most recent `gbrain-*.dump` in `~/.gbrain-backups/pg-dumps/`, creates the
`gbrain` database (refuses if non-empty unless you pass `--force`), runs
`pg_restore --no-owner --no-privileges --jobs=4`, and verifies via row counts.

If `~/.gbrain-backups/pg-dumps/` is empty, the `gbrain-backups` repo wasn't
cloned correctly — re-run `bootstrap.sh`.

### Step 4 — Restart gateway + refresh gbrain tokens

```sh
openclaw gateway restart
~/.openclaw/bin/gbrain-token-refresh.sh
```

The second command does Dynamic Client Registration with gbrain, mints
per-agent tokens, and patches them into `openclaw.json`. This resolves the
`${GBRAIN_TOKEN_*}` placeholders.

> **Note:** `gbrain-token-refresh.sh` is **site-specific and not bundled** — it
> talks to *your* gbrain instance's OAuth/`/register` endpoint, so you supply it
> (see [gbrain's auth docs](https://github.com/garrytan/gbrain)). If your gbrain
> runs without auth (the common local-only default), you can skip this step and
> leave the `${GBRAIN_TOKEN_*}` placeholders empty.

### Step 5 — Rebuild QMD index

```sh
./dr/restore-qmd.sh
```

This verifies all QMD collection source paths exist, runs `qmd update` to build
the BM25 index, and `qmd embed` to generate vector embeddings.

**First run downloads model weights** to
`~/.openclaw/agents/main/qmd/xdg-cache/qmd/models/`. The download is the slow
part.

### Step 6 — Pair Telegram bots

For each agent (main, dev, …):

1. Confirm the bot token in your local secrets file is correct (re-issued
   from `@BotFather` if needed — see `dr/secrets/README.md`).
2. Pair the device via the `device-pair` plugin:

   ```sh
   openclaw plugin device-pair --agent <agent-name>
   ```

3. Confirm by sending a `/start` from your Telegram app to each bot.

### Step 7 — Smoke test

```sh
./dr/smoke-test.sh
```

Expect `FAIL=0`. Workspace `dirty files` warnings are normal once agents start
running — they're not failures.

### Step 8 — Re-run `openclaw auth` for Codex

```sh
openclaw auth
```

Pick the OpenAI Codex provider and complete the OAuth flow. This re-creates the
`auth.profiles["openai:..."]` entry.

### Step 9 — Re-create openclaw cron jobs

The scheduled LaunchAgent jobs are declared in
[`../launchd/jobs.yaml`](../launchd/jobs.yaml) and installed by
`launchd/install-launchagents.sh`. Any openclaw *cron* jobs (those managed by
`openclaw cron`, not LaunchAgents) are NOT restored automatically — openclaw has
no `cron import` command yet. Re-create them by hand from your snapshot:

```sh
openclaw cron add --schedule "<cron expr>" --account "<account>" \
  --target "<channel>" --message "<prompt>"
```

---

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `bootstrap.sh` fails at `gh auth login` | No GitHub PAT | Re-issue from https://github.com/settings/tokens with `repo` + `read:org` scopes |
| `qmd` command is "not found" after bootstrap | Alias not loaded | Open a new terminal, or `source ~/.zshrc` |
| `restore-workspaces.sh` aborts on `${GH_ORG}` | `GH_ORG` not exported | `export GH_ORG=<your-org>` and re-run |
| `restore-gbrain.sh` says "No dumps found" | `gbrain-backups` repo wasn't cloned | Check `~/.gbrain-backups/pg-dumps/`. Re-run `bootstrap.sh` |
| `restore-gbrain.sh` says "DB exists with N tables" | Old data still present | Either accept it (and skip restore) or pass `--force` to drop+recreate |
| `restore-qmd.sh` hangs on model download | Slow / interrupted download | Cancel (Ctrl+C), remove the partial model dir, and re-run |
| `restore-qmd.sh` says "missing collection paths" | Workspaces didn't clone | Re-run `bootstrap.sh` — verify each path in the manifest exists |
| `openclaw doctor` errors on `${VAR}` | Placeholders not filled in | Edit `~/.openclaw/openclaw.json` per `dr/secrets/README.md` |
| LaunchAgents not loaded (`smoke-test.sh` warns) | First boot after install | Re-run `launchd/install-launchagents.sh` |
| Telegram bots silent | Tokens wrong or pairing not done | Re-run `device-pair`, check `~/.openclaw/credentials/telegram-pairing.json` exists |
| `gbrain` :8182 not responding | Postgres not running or gbrain service crashed | `brew services start postgresql@17`; `openclaw gateway restart`; check `~/.gbrain/logs/` |

---

## What gets restored automatically vs manually

**Automatic** (one of the scripts handles it):

- Brew formulae + npm globals
- All git repos in the manifest
- LaunchAgents (rendered + loaded)
- Postgres role + database
- gbrain data (from latest dump)
- QMD index + vector embeddings
- openclaw.json structure (template)

**Manual** (you do these by hand using `dr/secrets/README.md` as a checklist):

- Re-issue provider API keys (Anthropic, Gemini, Tavily, Brave, GitHub PAT)
- Re-create Telegram bot tokens via @BotFather
- Local secrets file contents (Telegram tokens + Gateway token)
- Telegram device pairing (one per bot)
- Codex OAuth profile

These are deliberately not in the repo because the secrets themselves don't
belong in git.

---

## What is NOT covered by this repo

- **macOS app settings** — restore via Time Machine or iCloud sync.
- **SSH keys** — restore via a password manager, Time Machine, or generate new
  ones and re-add to GitHub.
- **Browser sessions** — re-login as needed.
- **Personal git config** — `git config --global` your name + email.
- **Editor settings** — sync via the app's own sync feature.

The scope here is the OpenClaw operational stack and your irreplaceable gbrain
data. Everything else is regenerable from other sources.

---

## Verification at the end

After Step 7's `smoke-test.sh` reports `FAIL=0`, sanity check the full loop:

1. Send a message to the main agent on Telegram — expect a reply.
2. `gbrain query "test"` from terminal — expect results.
3. `qmd query "identity"` — expect hits from your workspace collections.
4. `openclaw cron list` — expect your cron jobs.

If all four work, the stack is fully restored.

---

## Uninstall / teardown

`bootstrap.sh` makes three kinds of change. Reverse them in this order. **Back up
first** — `${OPENCLAW_HOME}` holds your workspaces, memory, and gbrain data.

**1. Unload + remove the LaunchAgents** (derives the labels from `jobs.yaml`):

```bash
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
python3 - launchd/jobs.yaml <<'PY' | while read -r label; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || launchctl unload "$HOME/Library/LaunchAgents/$label.plist" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
  echo "removed $label"
done
import sys, yaml
for j in (yaml.safe_load(open(sys.argv[1])) or {}).get('jobs') or []:
    print(j['label'])
PY
```

**2. Undo the `~/.zshrc` edits** — bootstrap appends two blocks: a `# Bun` PATH
line and a `# QMD` alias. Delete those two blocks by hand (open `~/.zshrc`), then
open a new terminal.

**3. Remove installed packages + data (optional, deliberate):**

- Homebrew packages, `bun`, `qmd`, and `gbrain` were installed globally — remove
  only if nothing else uses them (`brew uninstall <pkg>`, etc.).
- The Postgres `gbrain` database: `dropdb gbrain` (this is real data — be sure).
- `${OPENCLAW_HOME}` itself: delete **only after** backing up workspaces + memory.
  Your workspace git remotes are the durable copy; the gbrain DB is not unless you
  have a recent `pg-backup`.

There is no single uninstall script by design — teardown touches global packages
and irreplaceable data, so each step is deliberate.
