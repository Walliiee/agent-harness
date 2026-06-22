#!/usr/bin/env bash
# gbrain-dreams-purge: delete any re-ingested dream pages from gbrain Postgres.
# Idempotent. Silent on 0 deleted. One stdout line on N>0 deleted.
# Files on disk are never touched.

set -u

PSQL=/opt/homebrew/opt/postgresql@17/bin/psql

SQL="WITH del AS (
  DELETE FROM pages
  WHERE slug LIKE 'memory/dreaming/%'
     OR slug = 'dreams'
     OR slug LIKE 'memory/.dreams/%'
  RETURNING source_id
)
SELECT COUNT(*) || '|' || COALESCE(string_agg(DISTINCT source_id, ',' ORDER BY source_id), '')
FROM del;"

result=$("$PSQL" -U gbrain -d gbrain -tAc "$SQL" 2>&1)
status=$?

if [ "$status" -ne 0 ]; then
  printf 'dreams-purge: psql failed: %s\n' "$result" >&2
  exit 1
fi

count="${result%%|*}"
sources="${result#*|}"

# Strip whitespace
count="${count// /}"

if [ -z "$count" ] || [ "$count" = "0" ]; then
  exit 0
fi

if [ -n "$sources" ]; then
  printf 'dreams-purge: %s pages deleted (sources: %s)\n' "$count" "$sources"
else
  printf 'dreams-purge: %s pages deleted\n' "$count"
fi
exit 0
