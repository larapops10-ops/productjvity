# PostgreSQL setup

The local development database is named `productjvity`. After starting Postgres.app, apply the initial schema:

```sh
cd "/Users/lara/Documents/Codex/2026-10-04/co/Productjvity Build"
sh scripts/apply-postgres-migration.sh
```

Verify the tables:

```sh
/Applications/Postgres.app/Contents/Versions/18/bin/psql -d productjvity -c "\\dt"
```

The current Ruby prototype still reads its local JSON store. The next migration step is to move those runtime reads and writes to these PostgreSQL tables, preserving the JSON file as a rollback backup until verification is complete.

## Import existing prototype data

After verifying the database connection, run this once. It inserts records without deleting the JSON source file or replacing an existing row with the same ID.

```sh
/Users/lara/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node apps/api/src/import-json-to-postgres.js
```
