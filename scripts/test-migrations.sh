#!/bin/zsh
# Applies all migrations to a throwaway local Postgres database and runs the SQL tests.
# Requires PostgreSQL (brew install postgresql@17). No Docker or Supabase account needed.
set -euo pipefail
# Postgres on macOS refuses to start with some locale setups ("multithreaded during startup").
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

ROOT=${0:A:h:h}
PG_BIN=${PG_BIN:-$(brew --prefix postgresql@17 2>/dev/null)/bin}
DATA=$(mktemp -d)
# Unix socket paths are limited to ~100 characters, so keep the socket in a short directory.
SOCK=$(mktemp -d /tmp/bartepg.XXXX)
PORT=${PORT:-54329}
LOG="$DATA/postgres.log"

cleanup() { "$PG_BIN/pg_ctl" -D "$DATA" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DATA" "$SOCK"; }
trap cleanup EXIT

"$PG_BIN/initdb" -D "$DATA" -U postgres --auth=trust >/dev/null
"$PG_BIN/pg_ctl" -D "$DATA" -o "-p $PORT -k $SOCK" -l "$LOG" start -w >/dev/null || { cat "$LOG"; exit 1; }

PSQL=("$PG_BIN/psql" -h "$SOCK" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q -X)

"${PSQL[@]}" -f "$ROOT/supabase/tests/supabase_stub.sql"
for migration in "$ROOT"/supabase/migrations/*.sql(N); do
  echo "→ ${migration:t}"
  "${PSQL[@]}" -f "$migration"
done
for test in "$ROOT"/supabase/tests/*_test.sql(N); do
  echo "✓ ${test:t}"
  "${PSQL[@]}" -o /dev/null -f "$test"
done
echo "All migrations and SQL tests passed."
