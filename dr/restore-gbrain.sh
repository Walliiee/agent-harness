#!/usr/bin/env bash
# restore-gbrain.sh — restore gbrain postgres database from the latest
# off-machine pg-dump in ~/.gbrain-backups/pg-dumps/.
#
# Idempotent in the trivial sense (re-running on a populated DB requires
# --force). Original dumps are produced with `pg_dump -U gbrain -d gbrain -Fc`
# (see ~/.gbrain/pg-backup.sh:81), so we restore with pg_restore against the
# matching db.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.gbrain-backups/pg-dumps"
DB_NAME="gbrain"
DB_ROLE="gbrain"

FORCE=0
DUMP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --dump)  DUMP="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--force] [--dump <path>]

  --force        Drop existing gbrain database before restore (DATA LOSS).
                 Without --force, refuses to restore over a non-empty DB.
  --dump <path>  Restore from a specific dump file (default: latest in
                 $BACKUP_DIR).
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '   %s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '   %s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '   %s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }
abort(){ err "$1"; exit 1; }

# ----- locate postgres binaries -----
step "Locate postgres@17"
PG_PREFIXES=(/opt/homebrew/opt/postgresql@17 /usr/local/opt/postgresql@17)
PG_BIN=""
for p in "${PG_PREFIXES[@]}"; do
  if [[ -x "$p/bin/pg_restore" ]]; then PG_BIN="$p/bin"; break; fi
done
[[ -n "$PG_BIN" ]] || abort "postgresql@17 not installed — run bootstrap.sh first"
ok "Using $PG_BIN"
export PATH="$PG_BIN:$PATH"

# ----- check service running -----
step "Check postgres service"
if ! pg_isready -h localhost -p 5432 -q; then
  warn "postgres not accepting connections — attempting brew services start"
  brew services start postgresql@17 || abort "could not start postgres"
  # Wait up to 20s
  for i in {1..20}; do
    pg_isready -h localhost -p 5432 -q && break
    sleep 1
  done
  pg_isready -h localhost -p 5432 -q || abort "postgres still not ready after 20s"
fi
ok "postgres accepting connections on localhost:5432"

# ----- ensure gbrain role -----
step "Ensure role '$DB_ROLE' exists"
ROLE_EXISTS=$(psql -tA -d postgres -c "SELECT 1 FROM pg_roles WHERE rolname='$DB_ROLE';" 2>/dev/null | tr -d ' ')
if [[ "$ROLE_EXISTS" == "1" ]]; then
  ok "Role '$DB_ROLE' already exists"
else
  warn "Creating role '$DB_ROLE' (LOGIN, CREATEDB)"
  psql -d postgres -c "CREATE ROLE $DB_ROLE WITH LOGIN CREATEDB;" || abort "CREATE ROLE failed"
fi

# ----- pick dump file -----
step "Select dump file"
if [[ -z "$DUMP" ]]; then
  DUMP="$(ls -1t "$BACKUP_DIR"/gbrain-*.dump 2>/dev/null | head -1)"
  [[ -n "$DUMP" ]] || abort "No dumps found in $BACKUP_DIR — has gbrain-backups been cloned?"
fi
[[ -f "$DUMP" ]] || abort "Dump not found: $DUMP"
DUMP_BYTES=$(stat -f%z "$DUMP" 2>/dev/null || stat -c%s "$DUMP")
ok "Restoring from: $(basename "$DUMP")  ($((DUMP_BYTES/1024/1024)) MB)"

# ----- check existing DB -----
step "Check existing database"
DB_EXISTS=$(psql -tA -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" 2>/dev/null | tr -d ' ')
if [[ "$DB_EXISTS" == "1" ]]; then
  # Count tables in public schema; treat 0 as empty
  TABLE_COUNT=$(psql -tA -d "$DB_NAME" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' ')
  TABLE_COUNT="${TABLE_COUNT:-0}"
  if [[ "$TABLE_COUNT" -gt 0 ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      warn "DB exists with $TABLE_COUNT tables — dropping (--force given)"
      psql -d postgres -c "DROP DATABASE $DB_NAME;" || abort "DROP DATABASE failed"
      psql -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_ROLE;" || abort "CREATE DATABASE failed"
      ok "Database recreated empty"
    else
      err "Database '$DB_NAME' already exists with $TABLE_COUNT tables."
      err "Pass --force to drop and re-restore (DATA LOSS), or restore manually."
      exit 1
    fi
  else
    ok "Database '$DB_NAME' exists but is empty — proceeding"
  fi
else
  warn "Database '$DB_NAME' does not exist — creating"
  psql -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_ROLE;" || abort "CREATE DATABASE failed"
fi

# ----- restore -----
step "Restoring (this can take several minutes for large dumps)"
LOG="/tmp/gbrain-restore-$(date +%Y%m%d-%H%M%S).log"
if pg_restore \
    --dbname="$DB_NAME" \
    --no-owner \
    --no-privileges \
    --jobs=4 \
    --verbose \
    "$DUMP" >"$LOG" 2>&1; then
  ok "pg_restore completed"
else
  # pg_restore may exit non-zero on benign warnings (e.g. missing extensions)
  # Check whether any tables landed before declaring failure.
  warn "pg_restore exited non-zero — checking whether data was loaded anyway"
  warn "Full log at: $LOG"
fi

# ----- verify -----
step "Verify restore"
TABLE_COUNT=$(psql -tA -d "$DB_NAME" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d ' ')
ok "Tables in public schema: $TABLE_COUNT"
if [[ "$TABLE_COUNT" -eq 0 ]]; then
  err "Zero tables restored — see $LOG"
  exit 1
fi

# Sample row counts on the irreplaceable-data tables (best effort).
# These names are taken from the live 2026-06-02 schema (36 tables total).
for t in pages sources content_chunks raw_data timeline_entries takes facts links; do
  cnt=$(psql -tA -d "$DB_NAME" -c "SELECT count(*) FROM $t;" 2>/dev/null | tr -d ' ')
  if [[ -n "$cnt" ]]; then
    printf '   %s•%s %s: %s rows\n' "$c_blue" "$c_reset" "$t" "$cnt"
  fi
done

step "Done"
ok "gbrain restored from $(basename "$DUMP")"
ok "Next: run restore-qmd.sh to rebuild vector indices"
