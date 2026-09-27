# Moving to Postgres (if it's ever needed)

SQLite on the Pi is the right size for a group of friends (ADR 0001): one file, WAL mode, one
process, and backups with the online-backup API. Move only if something real forces it: several
backend processes or hosts, a managed database, or write contention you can measure (the
`friends_http_request_duration_seconds` histogram, contract section 1.13).

The design keeps the move cheap:
- UUIDs are generated in Python (UUIDv7);
- instants are UTC;
- enums are `varchar` (`native_enum=False`);
- queries are SQLAlchemy Core/ORM with no raw SQL in the services;
- every schema change is an Alembic migration.

What follows is the complete list of SQLite-specific spots, found by searching for `NOCASE`,
`sqlite_where`, `json_`, `PRAGMA` and `sqlite` in `backend/`.

## 1. Driver and engine (`core/db.py`, `core/config.py`)

- Add `psycopg[binary]` and use `DATABASE_URL=postgresql+psycopg://user:pass@host/friends`.
- `create_db_engine` sets SQLite pragmas on connect (`journal_mode=WAL`, `foreign_keys=ON`, …) and
  emits `BEGIN` / `BEGIN IMMEDIATE` itself (write sessions take the write lock up front). On
  Postgres:
  - skip the connect hook;
  - drop the `sqlite_begin` execution option, because Postgres' default `READ COMMITTED` plus
    row locks replace `BEGIN IMMEDIATE`;
  - enforce foreign keys always (there is nothing to switch on).
- Optimistic locking (`version` columns) already guards concurrent edits of the same row. Nothing
  else relies on SQLite's single-writer lock.
- `SQLITE_BUSY_TIMEOUT_MS` becomes irrelevant. Consider `statement_timeout` instead.

## 2. Case-insensitive text (`COLLATE NOCASE`)

These columns compare, sort and index case-insensitively for ASCII letters (contract section 1.10):
- `users.email`;
- `activities.title`;
- `categories.name`;
- `poll_options.label`.

Pick one of these:
- **`citext`** (`CREATE EXTENSION citext`): change the column type in a migration. Comparisons,
  unique constraints and `ORDER BY` stay case-insensitive with no query changes. This is closest
  to today's behaviour.
- **A nondeterministic ICU collation** (`CREATE COLLATION ci (provider = icu, locale =
  'und-u-ks-level2', deterministic = false)`): it also folds non-ASCII letters (É/é). That changes
  the unique rules the contract describes, so update section 1.10 if you choose it.
- **Plain text with `lower()`**: needs unique indexes on `lower(name)` and `func.lower()` in the
  filters and sorts. It takes the most code changes.

`polls.service._fold` mirrors NOCASE's ASCII-only folding in Python. Keep it in line with
whichever collation you choose.

## 3. Partial unique indexes (`sqlite_where`)

The following indexes use `sqlite_where=`:
- `categories`: names unique among top-level categories, and among a parent's subcategories;
- `memberships`: one owner per group.

Add the same predicate as `postgresql_where=` next to each `sqlite_where=`, then generate a migration.
Both dialects support partial indexes.

## 4. JSON (`activities.attributes`, the attribute filters)

The `attr` filters (contract section 8.7) call SQLite's JSON1 functions in
`features/activities/filters.py`: `json_type(attributes, '$.key')` and
`json_extract(attributes, '$.key')`. On Postgres:
- store `attributes` as `jsonb` (`sa.JSON().with_variant(JSONB(), "postgresql")`);
- `jsonb_typeof(attributes -> 'key')` replaces `json_type` (`number` instead of
  `integer`/`real`);
- `(attributes ->> 'key')::float` and `attributes ->> 'key'` replace `json_extract`.

Put a dialect switch in `attribute_condition`, or use SQLAlchemy's `Activity.attributes[key]`
accessors (`.as_float()`, `.as_string()`) together with a `jsonb_typeof` guard. The equality
comparison uses `COLLATE NOCASE`: use `ILIKE` without wildcards, or `citext`.

## 5. `LIKE`

SQLite's `LIKE` is case-insensitive for ASCII; Postgres' is case-sensitive. Two call sites need
`ilike`:
- the title search (`q`, `Activity.title.contains(...)`);
- the `contains` attribute filter.

SQLAlchemy's `.icontains(value, autoescape=True)` works on both dialects.

## 6. Migrations (`alembic/env.py`)

- `render_as_batch=True` exists for SQLite's limited `ALTER TABLE`. It is harmless on Postgres,
  but not needed.
- The foreign-keys-off / `PRAGMA foreign_key_check` dance around migrations is SQLite-only. On
  Postgres, run migrations in one transaction (the default) and let the constraints check
  themselves.
- `UTCDateTime` stores naive UTC. On Postgres, keep `timestamp without time zone` (identical
  behaviour), or switch to `timestamptz` in one migration. The type decorator already converts
  at the boundary.

## 7. Backups (`cli.py backup`, the `migrate` pre-migration backup)

- Both use the SQLite online-backup API and `PRAGMA integrity_check`. Replace them with
  `pg_dump --format=custom`, or use the provider's point-in-time recovery.
- Keep the `friends-*.db.gz` naming idea so that `friends_backups` and
  `friends_last_backup_timestamp_seconds` (section 1.13) keep working. Otherwise adapt
  `core/backups.py`.
- The deploy runbook's restore drill changes to `pg_restore`.

## 8. Several processes

The rate limiter (`core/ratelimit.py`) and the request metrics (`core/metrics.py`) live in
process memory. With more than one backend process:
- move the rate limits to Postgres (a small table with `INSERT ... ON CONFLICT`) or to Redis;
- scrape each process's `/metrics` separately (or use Prometheus' multiprocess mode).

## 9. Moving the data

1. Stop the app (`docker compose stop backend`) and take a final SQLite backup.
2. On an empty Postgres database, run `alembic upgrade head` with the Postgres `DATABASE_URL`.
3. Copy the tables in dependency order with a short script that reads with the SQLite engine and
   bulk-inserts with the Postgres engine. Use the models' `__table__` objects: they carry the
   types. The order is:
   1. `users`, `refresh_tokens`;
   2. `groups`, `memberships`, `invites`, `group_log`;
   3. `categories`, `activities`, `activity_interests`;
   4. `wheel_spins`;
   5. `polls`, `poll_options`, `poll_votes`;
   6. `events`, `event_exceptions`;
   7. `availability`.
4. Compare the row counts (`friends_rows` shows a few), start the app on Postgres and run the
   smoke checks from the deploy runbook.
5. Keep the SQLite file until you have restored a Postgres backup once.
