# `config/` — operational config (under DR)

Files here describe the **intended state** of the OpenClaw stack so
silent drift can be detected and corrected. They are NOT runtime config
(that's `${OPENCLAW_HOME}/openclaw.json`). These are
declarations the doctors compare against, plus the sanitized templates a
fresh-machine rebuild copies into place.

Safe to ship — no secrets. Secret-shaped values are redacted
(`<REDACTED_*>`) and `${VAR}` template bindings are preserved.

---

## `gbrain-sources.json.template` — source → path manifest

### What it is

Authoritative declaration of which `local_path` each approved gbrain
source should have in the Postgres `sources` table. One entry per
source. Sources intentionally excluded from gbrain must be absent from
this manifest; if they appear in the live table, the doctor reports
`MISSING_IN_MANIFEST`.

### Why it exists

A rebuild (e.g. a PGLite → Postgres migration, or a restore) can
re-register a source with the wrong `local_path` — for example, the
`default` source pointing at a sibling agent's workspace instead of its
own. Such a misconfig is silent: every hourly `gbrain sync` re-walks the
wrong tree and mixes the wrong agent's content into the federated query
view. This is a documented hallucination vector.

The bug is silent because:

1. `gbrain` has no `sources update` CLI — only direct SQL can change
   `local_path`. Nobody routinely reads it.
2. Sync errors don't fire — gbrain happily walks whatever path it's
   pointed at.
3. Query results look plausible because adjacent agent content overlaps.

Without a declarative cross-check, the same class of misconfig will
recur on any future rebuild/restore.

### How it's checked

A `gbrain-sources-doctor` script reads this manifest, queries the live
`sources` table, diffs, and reports drift. Wire it to run after every
sync (silent on clean):

```bash
gbrain-sources-doctor          # detect only, silent on clean
gbrain-sources-doctor --json   # machine-readable
gbrain-sources-doctor --fix    # auto-correct PATH_DRIFT via SQL
```

### Drift kinds

| Kind                 | Meaning                              | Auto-fixable |
| -------------------- | ------------------------------------ | ------------ |
| `PATH_DRIFT`         | declared.local_path ≠ actual         | Yes (`--fix`) |
| `MISSING_IN_DB`      | declared source not present in DB    | **No** — review |
| `MISSING_IN_MANIFEST`| unarchived source in DB but not declared | **No** — review |
| `ARCHIVED_LIVE`      | declared source archived in DB       | **No** — review |

`--fix` deliberately handles only `PATH_DRIFT`. Creating, deleting, or
un-archiving sources is a human decision — the script flags them so you
notice, but never automates them. Archived sources absent from the
manifest are ignored so intentionally excluded sources do not keep
raising drift. Archived sources must also have `config.syncEnabled=false`
and `local_path=NULL`; otherwise `gbrain sync --all` can still walk them.

### When to edit the manifest

Edit `gbrain-sources.json` **only** when the intended state legitimately
changes:

- Adding a new gbrain source → add an entry.
- Deliberately moving a source to a new path → update the entry first,
  then run `gbrain-sources-doctor --fix` to align the DB.
- Decommissioning a source → remove the entry (after archiving the
  source via gbrain CLI).
- Excluding an agent from gbrain entirely → remove the entry and remove
  or archive the live source.

Do **not** edit the manifest to silence a drift you don't understand.
A drift report is a question: "why did this happen?" Investigate, then
either fix the DB (`--fix`) or update the manifest (intentional change).

### Repair playbook — recovering from a recurrence

If the next rebuild/restore baked the wrong `local_path` again:

```bash
# 1. Confirm drift
gbrain-sources-doctor

# 2. Stop the sync LaunchAgent so it can't write while you fix
launchctl bootout gui/$(id -u)/ai.gbrain.postgres-sync

# 3. Cascade pre-check — confirm corrupt content footprint is small
psql -U gbrain -h localhost -d gbrain <<'SQL'
SELECT 'facts'        AS tbl, COUNT(*) FROM facts
  WHERE source_id='default' AND source_markdown_slug LIKE 'other-agent/%'
UNION ALL
SELECT 'pages_live'   AS tbl, COUNT(*) FROM pages
  WHERE source_id='default' AND slug LIKE 'other-agent/%' AND deleted_at IS NULL;
SQL

# 4. Auto-fix the path drift
gbrain-sources-doctor --fix

# 5. Re-sync from the now-correct path with prune to clear stale pages
gbrain sync --source default --full --prune

# 6. Restart the LaunchAgent
launchctl bootstrap gui/$(id -u) \
  ~/Library/LaunchAgents/ai.gbrain.postgres-sync.plist

# 7. Verify
gbrain-sources-doctor
```

---

## `openclaw.json.template`

A sanitized snapshot of `${OPENCLAW_HOME}/openclaw.json`, with
secret-shaped values (`*_API_KEY`, `*_TOKEN`, `*_SECRET`,
`Authorization`) redacted but `${VAR}` template bindings preserved. In
the live system this is refreshed by a presync hook that calls a
config-sanitizer before each DR push.

On a fresh-machine rebuild: copy this template to
`${OPENCLAW_HOME}/openclaw.json` and re-add the API keys. See
`dr/secrets/README.md` for the enumeration of which keys live where.

This template ships a **2-agent example** (`main` + `dev`). Add more
agents by appending blocks to `agents.list`, `channels.telegram.accounts`,
`bindings`, and the various allowlists. Keep one `agents.map.template`
row per agent in sync.

---

## `agents.map.template`

The single place that declares your agents (`<agent-id> <workspace-dir>
<persona-label>`). In the original system this mapping was hardcoded
across several scripts; the harness reads it from here instead, so
adding/renaming an agent is a one-file edit.

---

## Scheduler state snapshots (live system)

In the live system, cron-job and commitment snapshots are refreshed
periodically by a state-snapshot hook so the scheduler state is
recoverable on a fresh-machine rebuild. There is no bulk `cron import`
CLI yet — jobs are re-added from the snapshot by hand or by a small
script. See `launchd/jobs.yaml` for the declarative job set this harness
ships.

State **not** under DR:
- The runtime sqlite (large binary, churns constantly) — deliberately
  excluded; pushing every cycle would balloon the repo and the content
  is reconstructable from the interaction log + the cron snapshots.

---

## Silent-break risks (worth monitoring)

The defenses here (this manifest + the doctor + the sync wiring) compound
only as long as each link survives. Known ways they get silently broken:

- The sync script is regenerated by a future `gbrain upgrade` or
  `openclaw doctor --fix`, stripping the doctor chain.
- The DR walker is regenerated, losing the config-sanitize hook → the
  sanitized template goes stale.
- Supporting bin scripts (doctor, sanitizer) get moved, renamed, or lose
  `+x`.
- This manifest gets deleted or its top-level `sources` key removed.
- Someone edits the manifest to silence a drift instead of investigating.
- `dr/workspaces.manifest.yaml.template` is rewritten with stale paths → the
  restore script silently skips whichever component URL disappeared.
- A wiki page is committed with a `description` shorter than 30 chars,
  missing entirely, or carrying an unquoted `:` in its value (silent
  gbrain YAML parse failure). Retrieval rank collapses for that page; a
  structural validator won't catch it — a retrieval-audit will.

### The weekly invariants check

An `invariants-check` script fingerprints all of the above and runs
weekly via a LaunchAgent (Sunday 05:00). On any failure it writes one
line per failure to a log, a full report under `incidents/`, and exits
non-zero. Silent on PASS. See `launchd/jobs.yaml`.

If this LaunchAgent itself gets unloaded or the script removed, the
check stops running. `launchctl list | grep invariants` should return
one line. The plist is shipped under DR so a restore brings it back.
