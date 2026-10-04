#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PSQL="${PSQL:-/Applications/Postgres.app/Contents/Versions/18/bin/psql}"

for migration in "$PROJECT_ROOT"/db/migrations/*.sql; do
  "$PSQL" -d productjvity -v ON_ERROR_STOP=1 -f "$migration"
done
