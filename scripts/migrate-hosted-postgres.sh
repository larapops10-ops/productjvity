#!/bin/sh
# Create Productjvity's empty production schema without ever writing the
# hosted database address to a file or shell history.
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PSQL="${PSQL:-/Applications/Postgres.app/Contents/Versions/18/bin/psql}"

if [ ! -x "$PSQL" ]; then
  PSQL="$(command -v psql || true)"
fi

if [ -z "$PSQL" ]; then
  echo "PostgreSQL's psql tool could not be found. Open Postgres.app, then try again."
  exit 1
fi

printf "Paste the pooled Neon connection string (it will stay hidden), then press Return: "
stty -echo
trap 'stty echo 2>/dev/null || true' EXIT HUP INT TERM
IFS= read -r PRODUCTJVITY_DATABASE_URL
stty echo
trap - EXIT HUP INT TERM
printf "\nSetting up the online Productjvity database…\n"

if [ -z "$PRODUCTJVITY_DATABASE_URL" ]; then
  echo "No connection string was entered; nothing was changed."
  exit 1
fi

for migration in "$PROJECT_ROOT"/db/migrations/*.sql; do
  "$PSQL" "$PRODUCTJVITY_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$migration"
done

"$PSQL" "$PRODUCTJVITY_DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "select current_database() as database, current_user as user;"

echo "Online database ready. It is intentionally empty, so your public app starts clean."
