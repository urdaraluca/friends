# Friends API v1 contract

**Status:** authoritative for milestones M1–M10 (reconciled 2026-09-25 from the design drafts, the
critic's resolutions and the approved plan). This is the single source of truth for implementers.
`backend/openapi.json` is generated from the code and must agree with this document; when a PR
changes one, it changes the other.

**Notation used throughout**
- `T?` means nullable (`T | None`). In responses the field is always present (value `null`); in
  requests it may be omitted and then defaults to `null` unless a default is shown (`= x`).
- `uuid` is a UUIDv7 string, `datetime` an ISO-8601 UTC instant, `date` a `YYYY-MM-DD` string
  (`ApiDate`), `Color` a `#RRGGBB` string.
- "member", "admin", "owner" are roles in the group that owns the resource. "admin+" means admin
  or owner.

---

## 1. Conventions

### 1.1 Base URL, same-origin hosting, docs

- API prefix: **`/api/v1`**. Every path in section 8 is relative to it.
- **One origin, one container.** The backend image serves the Flutter web build and the API. Request
  routing, in order:
  1. `/api/v1/...` goes to the API routers.
  2. Any other `/api/...` path returns a **problem+json 404 `not_found`** (an existing path with the
     wrong method returns 405 `method_not_allowed`). The API never returns HTML. A path counts as
     `/api/...` both as sent and once normalised (empty and `.` segments dropped, `..` resolved), so
     `//api/v1/health` is a 404 too, never the app shell.
  3. `GET /.well-known/assetlinks.json` returns JSON built from env `ANDROID_CERT_SHA256`
     (comma-separated `AA:BB:…` fingerprints, e.g. release and debug keys), or problem+json 404
     when that variable is empty:
     ```json
     [{"relation": ["delegate_permission/common.handle_all_urls"],
       "target": {"namespace": "android_app",
                  "package_name": "io.github.urdaraluca.friends",
                  "sha256_cert_fingerprints": ["<each ANDROID_CERT_SHA256 entry>"]}}]
     ```
  4. Other `GET`/`HEAD` requests are served from `WEB_DIR` (`/app/web` in the image) **only when
     `WEB_DIR/index.html` exists**. An existing file is returned as is. Otherwise, if the last
     segment of the normalised path contains no `.`, `index.html` is returned with 200 (SPA fallback,
     e.g. `/join/ABCDEFGHJK`, `/groups/<id>/backlog`). Otherwise the response is 404. With no web
     build (dev, tests), these paths return 404.
  5. Other methods outside `/api/` return 405.
- **Caching.** Every response served from `WEB_DIR` sends `Cache-Control: no-cache`: files,
  SPA-fallback responses and their 304s, under any spelling of the path. They keep the StaticFiles
  `ETag` and `Last-Modified`, so an unchanged file costs a 304. A Flutter web build names its files
  without a content hash (`flutter_bootstrap.js` loads `main.dart.js`, `canvaskit/…` and
  `assets/…` by fixed names), so without this a browser could keep a heuristically cached old
  `main.dart.js` or CanvasKit after a release. API responses send `Cache-Control: no-store`.
- Docs: OpenAPI at `/api/v1/openapi.json`, Swagger UI at `/api/v1/docs`. Both exist only when
  `DOCS_ENABLED=true` (the default in dev and test; false in prod). No ReDoc.
- The OpenAPI `info.version` is the fixed string `"1"`. `APP_VERSION` never appears in the schema,
  so the committed snapshot doesn't change on every release; `/health` reports it instead.
- **CORS:** production has none, because the web app is same-origin. `CORS_ORIGINS` (exact
  origins, comma-separated) is empty by default. A fixed localhost origin regex
  (`^https?://(localhost|127\.0\.0\.1)(:\d+)?$`, not configurable) is added **only when
  `APP_ENV=dev`**, so the Flutter web dev server on any local port works. The
  middleware uses `allow_credentials=False`, allows headers `Authorization, Content-Type,
  X-Request-ID`, exposes `X-Request-ID, Retry-After`, and sets `max_age=600`.

### 1.2 Identifiers

- **UUIDv7** everywhere, generated on the server with stdlib `uuid.uuid7()` (Python 3.14). Stored as
  SQLAlchemy `Uuid` (CHAR(32) hex on SQLite). On the wire: lowercase hyphenated strings
  (`format: uuid`).
- Clients never create IDs in the MVP.
- A path parameter that isn't a valid UUID returns 422 `validation_error` (`path.<name>`).
- The two non-UUID identifiers are invite codes (section 4.7) and occurrence keys (section 5.6).

### 1.3 Time, dates and timezones

- **Instants** are stored through the `UTCDateTime` TypeDecorator:
  - on bind it **raises on naive datetimes** (a programming error, never a user error), converts
    aware values to UTC and stores them naive;
  - on load it returns aware UTC datetimes.
  - Ruff's `DTZ` rules forbid naive `datetime.now()` and similar in the codebase.
- **Instants on the wire** are ISO 8601 in UTC with a `Z` suffix, e.g. `2026-10-01T16:00:00Z`.
  Fractional seconds (up to 6 digits) may appear, and clients must accept them.
- **Instants in requests** are Pydantic `AwareDatetime`. Any UTC offset is accepted and converted to
  UTC. A value without an offset gets 422 `validation_error`. The Flutter client always sends
  `.toUtc()` values (section 12).
- **Dates** use `ApiDate = Annotated[date, BeforeValidator(parse_api_date)]` for every date body field
  and date query parameter (`due_date`, `due_before`, `start_date`, `end_date`, `from`, `to`,
  `WheelFilters.due_before`).
  - Accepted: `YYYY-MM-DD`, or a **midnight** date-time matching
    `^(\d{4}-\d{2}-\d{2})(?:[T ]00:00(?::00(?:\.0{1,6})?)?Z?)?$`. That covers Dart's
    `toIso8601String()` and `toString()` for a local or UTC midnight. The date part is taken as is
    and **never converted between zones**.
  - Rejected with 422: any non-midnight time (`2026-10-01T21:00:00Z` is already 2 October in
    Bucharest) and any explicit non-`Z` offset.
  - Output is always `YYYY-MM-DD`.
- **Timezones** are IANA names validated against `zoneinfo.available_timezones()`. The `tzdata` PyPI
  package is a runtime dependency (Windows has no IANA database). Invalid values are handled like
  this:
  - `POST /auth/register`: stored as `UTC`, no error (devices sometimes report non-IANA names).
  - The calendar `tz` query parameter falls back to the caller's `users.timezone`. The response's
    `tz` field shows the zone actually used.
  - Everywhere else (`PUT /me`, groups, events): 422 `validation_error`.
- **Floating dates** (all-day events, birthdays, due dates) mean the same calendar date in every
  timezone.

### 1.4 JSON and HTTP conventions

- JSON fields are **snake_case**, with no aliases in body or response models. The only aliases are
  the calendar query parameters `from` and `to` (Python `from_`/`to` with `Query(alias=...)`).
- Request models **ignore unknown fields** (`extra="ignore"`), so older app builds keep working when
  a field is removed.
- Responses always include every schema field. Missing values are `null`, never omitted. Empty lists
  are `[]`.
- **PUT bodies are the complete new state.** An omitted field is reset to its default, so clients
  send every field. The generated client does this (swagger_parser `include_if_null: false`; see
  [ADR 0003](../adr/0003-client-codegen.md) for why `false`).
- **No request field gives "omitted" and "null" different meanings.** The generated Dart client
  can't tell them apart.
- **Strings** are trimmed (`str_strip_whitespace=True`).
  - An optional string that is empty after trimming is stored as `null`. This happens before any
    format check, so `""` (or only whitespace) for an optional `Color`, `currency`, date or ID also
    means `null`.
  - A required string that is empty after trimming gets 422.
  - Lengths are counted in Unicode code points, after trimming.
- **Formats**
  - `Color` must match `^#[0-9A-Fa-f]{6}$` and is stored uppercase.
  - `currency` must match `^[A-Z]{3}$` (ISO 4217 shape; not checked against a list).
  - URLs (links, avatar, poll option `url`, `url`-type attributes) must be absolute `http`/`https`
    with a host, at most 2048 characters. They are stored as given, not normalized.
  - `email` is validated with `EmailStr` (email-validator, no DNS check), trimmed and lowercased,
    at most 254 characters.
- **Enums** are Python `StrEnum`s with lowercase snake_case values, named in the OpenAPI schema. They
  are stored as VARCHAR with **no database CHECK** (`Enum(native_enum=False, create_constraint=False)`),
  so adding a value needs no SQLite table rebuild. Clients must tolerate unknown values.
- **Array query parameters use repeated keys:** `?status=idea&status=planning`,
  `?kinds=one_time&kinds=birthday`. The `status[]=` form is not accepted.
- Query booleans are `true`/`false`.
- `204` responses have no body.
- Content types: `application/json` for requests and successes, `application/problem+json` for errors.

### 1.5 Error body (RFC 9457 problem+json)

```
Problem {
  type: str              # always "about:blank"
  title: str             # the HTTP reason phrase, e.g. "Unprocessable Content"
  status: int
  detail: str?           # English, human-readable, may change; clients never parse it
  code: str              # stable machine-readable code (section 2); clients branch on this
  errors: FieldError[]?  # set for 422 codes that point at input fields, else null
  request_id: str
}
FieldError { field: str, message: str, type: str }
```
- `field` is a dotted location.
  - Body fields drop the leading `body`: `title`, `links.2.url`, `attributes.imdb_rating`.
  - Query and path parameters keep their prefix: `query.from`, `path.group_id`.
- `type`:
  - for `validation_error`, the Pydantic error type (`missing`, `string_too_long`, …);
  - for `invalid_attributes`, a sub-reason from section 6.3;
  - for `invalid_rrule`, a sub-reason from section 5.2.
- Pydantic's `input`, `ctx` and `url` are **stripped**, so passwords are never echoed back.
- 401 responses carry `WWW-Authenticate: Bearer`. 429 responses carry `Retry-After: <seconds>`.
- Unhandled exceptions return 500 `internal_error` with a generic `detail`, and the traceback is
  logged together with the `request_id`. The catch-all runs **inside** the CORS middleware, so dev web
  clients still get CORS headers.
- Services raise `AppError(status, code, detail, errors)` subclasses: `NotFound` (404), `Forbidden`
  (403), `Conflict` (409), `Gone` (410), `Unprocessable` (422), `AuthError` (401),
  `RateLimited` (429). Services never import FastAPI.

### 1.6 Pagination

- Only lists that grow are paginated: activities and wheel spins.
- Query: `cursor` (opaque string) and `limit` (1..100, default 50).
- Response: `{items: [...], next_cursor: str?}`. `next_cursor` is `null` on the last page.
- For the MVP the cursor is base64url (no padding) of `{"o": <offset>}`. Clients treat it as opaque,
  so it can become keyset-based later without a client change. An invalid cursor gets 422
  `validation_error` (`query.cursor`).
- Every page is a concrete class (`ActivityPage`, `WheelSpinPage`), which keeps schema names clean.
- Every other list is unpaginated and bounded by the limits in section 1.9.

### 1.7 Writes, concurrency and side effects

- Editable resources use **full-object `PUT`**. Quick changes use small **command endpoints**:
  activity status, interest, vote, poll close/reopen, spin accept.
- **Optimistic locking on activities and events.**
  - `version` starts at 1.
  - A PUT must send the `version` it last read. On a mismatch the server returns 409
    `version_conflict` and changes nothing.
  - Every successful PUT increments `version`. So does any **server-side change to a field of the
    resource's Write schema**: category reassignment when a category is deleted, `owner_id`
    cleared when the owner leaves the group, or an event's `activity_id` cleared when its activity
    is deleted.
  - Status changes, interests, polls and linked events do **not** change `activity.version`.
- Groups, categories, polls and `/me` are last-write-wins.
- On `409 version_conflict` the client offers **"Reload" only**. There is no "Overwrite" button.
- Every mutation goes through the service layer. Every group-scoped mutation writes its `group_log`
  rows (section 3.2) in the same transaction.
- **GET handlers never write**: no last-seen updates and no lazy cleanup. Derived values are computed
  on read: invite status, poll `is_open`, filtering of stale attributes.

### 1.8 Auth header and request IDs

- Every non-public endpoint requires `Authorization: Bearer <access_token>`.
- `X-Request-ID`: the client's value is used if it matches `^[A-Za-z0-9._-]{1,64}$`; otherwise one is
  generated. It is echoed on every response and appears in problem bodies and in each access-log line
  (`method, path, status, duration_ms, client_ip, user_id, request_id`). The health endpoint is not
  access-logged.
- Authorization headers, passwords and tokens are never logged.

### 1.9 Limits

| What | Limit | Error when exceeded |
|---|---|---|
| Groups a user belongs to | 50 | 422 `limit_reached` |
| Members per group | 100 | 422 `limit_reached` |
| Categories per group (including subcategories) | 100 | 422 `limit_reached` |
| Category depth | 2 (category > subcategory) | 422 `category_depth_exceeded` |
| Field definitions per category (its own) | 12, so at most 24 effective on a subcategory | 422 `validation_error` |
| Category `position` | 0..1,000,000 | 422 `validation_error` |
| Links per activity | 10 | 422 `validation_error` |
| Invites returned by `list_invites` | the newest 100 (older ones, almost always expired, are left out) | – |
| Polls per activity | 10 | 422 `limit_reached` |
| Options per poll | 2..20 | create: `validation_error`; add or delete: `limit_reached` |
| `option_ids` in one vote | 0..20 | 422 `validation_error` |
| Wheel candidates per spin | 2..50 | fewer than 2: 422 `not_enough_candidates`; more than 50 `activity_ids`: 422 `validation_error` |
| Page size (`limit`) | 1..100, default 50 | 422 `validation_error` |
| Calendar range | 1..400 days | over 400: 422 `range_too_large`; `to <= from`: 422 `validation_error` |
| Occurrences per event per calendar request | 1000 (safety net; extra ones are dropped) | – |
| Event duration | at most 30 days | 422 `validation_error` |
| RRULE `INTERVAL` / `COUNT` | 1..99 / 1..730 | 422 `invalid_rrule` |
| `estimated_cost` | 0..10,000,000 (whole units) | 422 `validation_error` |
| `q` (search) | 1..100 characters | 422 `validation_error` |

### 1.10 Storage conventions (SQLite)

- **Pragmas on every connection:** `journal_mode=WAL`, `synchronous=NORMAL`, `foreign_keys=ON`,
  `busy_timeout=5000`, `temp_store=MEMORY`. pysqlite runs with `isolation_level=None`, and the engine
  issues explicit `BEGIN` statements.
- **Two session factories on one engine:**
  - read sessions (`BEGIN DEFERRED`) for GET, HEAD and OPTIONS;
  - write sessions (`BEGIN IMMEDIATE`) for every other method, so write transactions never hit an
    instant `SQLITE_BUSY`.
  - Both use `expire_on_commit=False`. Services call `flush()` then `commit()` explicitly, and the
    dependency rolls back on error.
- **One uvicorn worker.** The in-process rate limiter relies on it.
- **Alembic:** `render_as_batch=True`. Migrations run with `foreign_keys=OFF`, then
  `PRAGMA foreign_key_check` must return no rows. `cli migrate` backs the database up first.
- **Naming convention** on `Base.metadata`:
  `ix_%(column_0_label)s`, `uq_%(table_name)s_%(column_0_name)s`,
  `ck_%(table_name)s_%(constraint_name)s`,
  `fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s`, `pk_%(table_name)s`.
- **Case-insensitive uniqueness** uses `COLLATE NOCASE` columns with plain (partial) unique indexes
  (`sqlite_where=`). There are no `lower(...)` expression indexes, because Alembic autogenerate can't
  compare them. NOCASE folds ASCII only, which is acceptable.
- JSON columns use SQLAlchemy `JSON` (TEXT). Their content is validated by the service layer before
  writing.
- `friends_api/db_models.py` imports every feature's `models.py`, so Alembic and the tests see the full
  metadata.

### 1.11 Server configuration (environment variables)

| Variable | Dev default | Prod | Notes |
|---|---|---|---|
| `APP_ENV` | `dev` | `prod` (set in the image) | `dev`, `test` or `prod` |
| `DATABASE_URL` | `sqlite:///./friends.db` | `sqlite:////data/friends.db` (set in the image) | |
| `JWT_SECRET` | insecure placeholder | **required**, at least 32 bytes | Startup fails in prod if it is missing, shorter than 32 bytes, or the placeholder |
| `ACCESS_TOKEN_TTL_MINUTES` | 15 | 15 | |
| `REFRESH_TOKEN_TTL_DAYS` | 30 | 30 | sliding lifetime |
| `REFRESH_SESSION_MAX_DAYS` | 180 | 180 | absolute cap per session |
| `REFRESH_REUSE_GRACE_SECONDS` | 60 | 60 | section 4.5 |
| `REGISTRATION_MODE` | `invite_only` | `invite_only` | `invite_only` or `open` |
| `PUBLIC_APP_URL` | `http://localhost:5000` | **required**, e.g. `https://friends.example.com` | Base of `Invite.url`; no trailing slash |
| `DOCS_ENABLED` | `true` | `false` | |
| `CORS_ORIGINS` | empty | empty | comma-separated; with `APP_ENV=dev` the fixed localhost regex (section 1.1) is also allowed |
| `WEB_DIR` | `/app/web` | `/app/web` | static hosting only when `index.html` exists there |
| `ANDROID_CERT_SHA256` | empty | the release fingerprint (plus debug if wanted) | `assetlinks.json` |
| `RATE_LIMIT_ENABLED` | `true` (tests: `false`) | `true` | |
| `ARGON2_TIME_COST` / `ARGON2_MEMORY_KIB` / `ARGON2_PARALLELISM` | 3 / 65536 / 4 | tune so one hash takes 0.1–0.5 s on the Pi | tests use 1 / 8 / 1 |
| `SQLITE_BUSY_TIMEOUT_MS` | 5000 | 5000 | |
| `LOG_LEVEL` / `LOG_FORMAT` | `INFO` / `console` | `INFO` / `json` | |
| `BACKUP_DIR` / `BACKUP_KEEP` | `./backups` / 14 | `/backups` / 14 | |
| `APP_VERSION` / `GIT_SHA` | `dev` / `unknown` | set by the image build | reported by `/health` |
| `FORWARDED_ALLOW_IPS` | – | `*` (safe only with the `127.0.0.1` port bind) | read by uvicorn (`--proxy-headers`) |

### 1.12 CLI (`python -m friends_api.cli <command>`)

| Command | Behaviour |
|---|---|
| `migrate` | If migrations are pending and the database file exists, writes a backup to `BACKUP_DIR/pre-migrate-<UTC timestamp>.db.gz`, then runs `alembic upgrade head` (foreign keys OFF, then `foreign_key_check`). The container entrypoint runs it on start. |
| `backup [--keep N]` | Copies the database with the SQLite online-backup API, runs `PRAGMA integrity_check` on the copy, gzips it and keeps the newest N (default `BACKUP_KEEP`). |
| `export-openapi [PATH]` | Writes `app.openapi()` to `backend/openapi.json` (default) with `indent=2`, UTF-8, LF line endings and a trailing newline. Works even when `DOCS_ENABLED=false`. |
| `create-user --email E --display-name N [--password-stdin]` | Creates a user **regardless of `REGISTRATION_MODE`**; this is how the first account is made. Prompts twice for the password unless `--password-stdin` is given. Exits non-zero if the email is taken. |
| `reset-password EMAIL [--password-stdin]` | Sets a new password, increments `token_version` and deletes all the user's refresh tokens. There is no SMTP in the MVP. |
| `seed-demo` | **Refuses when `APP_ENV=prod`** (exit code 2), and also when the demo users already exist. Creates 3 demo users (`demo1..3@example.com`, with the password printed), one group with the default categories, about 120 activities across all statuses and categories (movies with attributes), interests, events (one-time, weekly, monthly, yearly, birthdays, profile birthdays), polls with votes, and a few wheel spins. |

---

## 2. Error codes

Clients branch on `code`, never on `title` or `detail`. Every authenticated endpoint can also return
401 `unauthenticated`/`token_expired`; every endpoint with input can return 422 `validation_error`;
every endpoint with a group-scoped ID can return 404 `not_found`. Section 8 lists only the extra
codes for each endpoint.

| Code | HTTP | Meaning |
|---|---|---|
| `validation_error` | 422 | The request's shape or values are invalid; `errors[]` says where. |
| `unauthenticated` | 401 | Missing, malformed or invalid access token; `tv` mismatch (logout-all or password change); deleted user. The client logs out. |
| `token_expired` | 401 | The access token has expired. The client refreshes once and retries. |
| `invalid_credentials` | 401 | Login failed: unknown email, deleted account or wrong password. The response doesn't say which. |
| `refresh_invalid` | 401 | The refresh token is unknown, revoked or expired, or the session cap has been reached. |
| `refresh_reuse_detected` | 401 | A rotated refresh token was presented outside the grace rule. The whole family is revoked. |
| `wrong_password` | 422 | The current password is wrong on `/me/password` or `/me/deletion`. This is deliberately not a 401, so the client doesn't treat it as session expiry. |
| `weak_password` | 422 | The new password equals the account's email (case-insensitive) on `/auth/register` or `/me/password`. There is no `errors[]`; the client shows it on the password field. |
| `forbidden` | 403 | A member without the needed role or ownership. |
| `registration_closed` | 403 | `REGISTRATION_MODE=invite_only` and there was no `invite_code`. |
| `not_found` | 404 | The resource doesn't exist, **or the caller isn't a member of its group** (the two look identical); also unknown routes and unknown or malformed invite codes. |
| `method_not_allowed` | 405 | A known path with the wrong method. |
| `email_taken` | 409 | Registering with an email that already exists. |
| `name_taken` | 409 | A category name that already exists among its siblings (case-insensitive), or a new poll option whose label already exists on that poll (case-insensitive). Duplicate labels inside one `PollCreate` body are a 422 `validation_error`. |
| `version_conflict` | 409 | The PUT's `version` doesn't match the stored one. |
| `owner_must_transfer` | 409 | The owner tries to leave while the group has other members, or anyone tries to change the owner's role (use `transfer-ownership` instead). |
| `poll_closed` | 409 | A vote or new option on a closed poll (manually closed, or `closes_at` has passed). |
| `result_deleted` | 409 | Accepting a spin whose result activity has since been deleted. |
| `invite_expired` | 410 | The invite's `expires_at` has passed. |
| `invite_revoked` | 410 | The invite was revoked. |
| `invite_exhausted` | 410 | `use_count` has reached `max_uses`. |
| `invalid_reference` | 422 | An ID in the body (`category_id`, `parent_id`, `owner_id`, `activity_id`, `user_id`, `option_ids`, `activity_ids`) doesn't exist in this group, or the user isn't a member. `errors[]` names the field. |
| `category_depth_exceeded` | 422 | A third level, or giving a parent to a category that has subcategories. |
| `field_key_conflict` | 422 | A custom-field key is used both by a category and by its parent or one of its subcategories. |
| `field_type_change` | 422 | An existing custom-field key was given a different type. |
| `invalid_attributes` | 422 | An activity's `attributes` don't match the effective field definitions; `errors[]` gives one entry per bad key (section 6.3). |
| `invalid_rrule` | 422 | The RRULE is outside the allowed subset; `errors[0].type` gives the reason (section 5.2). |
| `range_too_large` | 422 | The calendar range is longer than 400 days. |
| `too_many_choices` | 422 | More than one `option_id` on a single-choice poll. |
| `not_enough_candidates` | 422 | A spin with fewer than 2 candidates. |
| `limit_reached` | 422 | A count limit from section 1.9 would be exceeded, or a poll would have fewer than 2 options. |
| `rate_limited` | 429 | Too many requests (section 4.9); comes with `Retry-After`. |
| `internal_error` | 500 | An unhandled server error. |

Removed from the drafts: `already_member` (accepting is idempotent) and `too_many_options` (replaced
by `limit_reached`).

---

## 3. Entities

### 3.1 Tables

Notation:
- `ts` is `UTCDateTime`, `uuid` is `Uuid`/CHAR(32), `json` is a JSON TEXT column.
- `-> t ACTION` is a foreign key to `t.id` with that `ON DELETE` action.
- Every FK column is indexed unless it leads the primary key or a composite index.
- Every table has `created_at ts not null`, set by the server. Tables whose rows can be edited also
  have `updated_at ts not null`, refreshed on every UPDATE. The exceptions are `refresh_tokens` and
  `wheel_spins`: their only changes are bookkeeping columns that carry their own timestamps
  (`used_at`, `revoked_at`, `replaced_by_id`; `accepted_at`, `accepted_by_id`), so they have no
  `updated_at`.
- User rows are **never hard-deleted** (they are anonymized, section 4.8), so `-> users SET NULL`
  only matters in tests.

```
users
  id                 uuid pk
  email              varchar(254) not null COLLATE NOCASE   -- trimmed + lowercased on input
                     UNIQUE uq_users_email                  -- deleted users hold 'deleted-<id>@invalid'
  password_hash      varchar(255) null      -- argon2id PHC string; null only for deleted users
  display_name       varchar(50)  not null
  avatar_url         varchar(2048) null     -- external URL in the MVP
  birthday_month     smallint null
  birthday_day       smallint null
  birthday_year      smallint null          -- optional; only the user ever sees it
  timezone           varchar(64) not null default 'UTC'
  locale             varchar(16) null       -- BCP 47; informational in the MVP (English only)
  token_version      int not null default 0 -- incremented = every access token dies at once
  last_login_at      ts null                -- written by POST /auth/login only
  deleted_at         ts null
  created_at, updated_at
  CHECK birthday_pair:  (birthday_month IS NULL) = (birthday_day IS NULL)
  CHECK birthday_year:  birthday_year IS NULL OR birthday_month IS NOT NULL
  CHECK birthday_range: birthday_month IS NULL OR (birthday_month BETWEEN 1 AND 12 AND birthday_day BETWEEN 1 AND 31)
  -- the service also checks the day against the month (Feb 29 allowed; with a year, it must be a real date)

refresh_tokens                              -- opaque, rotated, only the hash is stored
  id                 uuid pk
  user_id            uuid not null -> users CASCADE
  family_id          uuid not null (idx)    -- one family per login/register session (device)
  token_hash         char(64) not null UNIQUE -- sha256 hex of secrets.token_urlsafe(32)
  session_started_at ts not null            -- copied along the family; anchor for the 180-day cap
  expires_at         ts not null            -- min(issued_at + 30 d, session_started_at + 180 d)
  used_at            ts null                -- set when this token is rotated
  revoked_at         ts null
  replaced_by_id     uuid null -> refresh_tokens SET NULL
  device_label       varchar(100) null      -- copied along the family ("android" | "ios" | "web" | …)
  created_at                                -- no updated_at

groups
  id                 uuid pk
  name               varchar(60) not null
  description        varchar(500) null
  emoji              varchar(16) null
  color              char(7) null           -- '#RRGGBB'
  currency           char(3) not null default 'EUR'  -- default currency for activity costs
  timezone           varchar(64) not null   -- default for events; month/year boundaries for the recap
  members_can_invite bool not null default true
  created_by_id      uuid null -> users SET NULL
  created_at, updated_at

memberships
  group_id           uuid not null -> groups CASCADE
  user_id            uuid not null -> users CASCADE  (idx)
  role               varchar(10) not null   -- owner | admin | member
  show_birthday      bool not null default true      -- per-group opt-out
  invite_id          uuid null -> invites SET NULL   -- the invite used to join; null for the creator
  joined_at          ts not null            -- serves as created_at
  updated_at         ts not null
  PK (group_id, user_id)
  UNIQUE uq_memberships_owner (group_id) WHERE role = 'owner'
  -- at most one owner per group (index); at least one is guaranteed by the service.
  -- A transfer demotes the old owner before promoting the new one, in one transaction.

invites
  id                 uuid pk
  group_id           uuid not null -> groups CASCADE
  code               varchar(16) not null UNIQUE    -- 10 chars, Crockford base32 (section 4.7)
  created_by_id      uuid null -> users SET NULL
  expires_at         ts null                -- null = never expires (admin+ only)
  max_uses           int null               -- null = unlimited
  use_count          int not null default 0
  revoked_at         ts null
  created_at, updated_at
  CHECK use_count_nonneg: use_count >= 0
  CHECK max_uses_range:   max_uses IS NULL OR max_uses BETWEEN 1 AND 100
  CHECK uses_within_max:  max_uses IS NULL OR use_count <= max_uses
  -- Invite.url = {PUBLIC_APP_URL}/join/{code}

categories                                  -- per group, at most 2 levels deep
  id                 uuid pk
  group_id           uuid not null -> groups CASCADE
  parent_id          uuid null -> categories CASCADE   -- service: parent.parent_id IS NULL
  name               varchar(40) not null COLLATE NOCASE
  color              char(7) null           -- required for top-level (service); null on a subcategory = inherit
  icon               varchar(40) null       -- icon key (section 6.5) or an emoji
  position           int not null default 0
  field_defs         json not null default '[]'   -- list[FieldDef], section 6
  created_by_id      uuid null -> users SET NULL
  created_at, updated_at
  UNIQUE uq_categories_top_name (group_id, name) WHERE parent_id IS NULL
  UNIQUE uq_categories_sub_name (parent_id, name) WHERE parent_id IS NOT NULL
  INDEX  ix_categories_group_parent_position (group_id, parent_id, position)
  -- the NOCASE collation makes both unique indexes case-insensitive

activities                                  -- backlog items
  id                 uuid pk
  group_id           uuid not null -> groups CASCADE
  title              varchar(120) not null COLLATE NOCASE
  description        text null              -- <= 5000
  notes              text null              -- <= 5000
  category_id        uuid null -> categories SET NULL
  owner_id           uuid null -> users SET NULL      -- the responsible member; null = unowned
  created_by_id      uuid null -> users SET NULL
  status             varchar(12) not null default 'idea'  -- idea | planning | scheduled | done | dropped
  due_date           date null              -- "do it by"; not a calendar event
  estimated_cost     int null               -- WHOLE currency units (an estimate)
  currency           char(3) null
  cost_per_person    bool not null default true
  location_name      varchar(120) null
  address            varchar(300) null      -- the app opens maps from this text (no coordinates)
  links              json not null default '[]'   -- [{url, label}] <= 10
  attributes         json not null default '{}'   -- {key: string | number}; never stores nulls (section 6)
  version            int not null default 1
  status_changed_at  ts not null
  completed_at       ts null                -- set on -> done, cleared when leaving done (recap)
  created_at, updated_at
  CHECK cost_range:    estimated_cost IS NULL OR estimated_cost BETWEEN 0 AND 10000000
  CHECK cost_currency: (estimated_cost IS NULL) = (currency IS NULL)
  INDEX (group_id, status, created_at)
  INDEX (group_id, category_id)
  INDEX (group_id, owner_id)
  INDEX (group_id, due_date)

activity_interests
  activity_id        uuid not null -> activities CASCADE
  user_id            uuid not null -> users CASCADE  (idx)
  created_at
  PK (activity_id, user_id)

events                                      -- calendar series; occurrences are computed
  id                 uuid pk
  group_id           uuid not null -> groups CASCADE
  kind               varchar(10) not null   -- one_time | recurring | birthday
  title              varchar(120) not null
  description        text null              -- <= 5000
  category_id        uuid null -> categories SET NULL
  activity_id        uuid null -> activities SET NULL  (idx)   -- a scheduled backlog item
  all_day            bool not null
  starts_at          ts null                -- timed: start instant of the FIRST occurrence
  ends_at            ts null                -- timed: end instant of the first occurrence
  start_date         date null              -- all-day: first day of the first occurrence
  end_date           date null              -- all-day: last day, inclusive
  timezone           varchar(64) not null   -- wall clock used for expansion; default groups.timezone
  rrule              varchar(200) null      -- canonical restricted RRULE, no DTSTART (section 5)
  location_name      varchar(120) null
  address            varchar(300) null
  window_start       ts not null            -- computed superset search window (section 5.4)
  window_end         ts null                -- null = the series never ends
  version            int not null default 1
  created_by_id      uuid null -> users SET NULL
  created_at, updated_at
  CHECK timing:     (all_day AND start_date IS NOT NULL AND end_date IS NOT NULL
                      AND starts_at IS NULL AND ends_at IS NULL)
                 OR (NOT all_day AND starts_at IS NOT NULL AND ends_at IS NOT NULL
                      AND start_date IS NULL AND end_date IS NULL)
  CHECK kind_rrule: (kind = 'one_time') = (rrule IS NULL)
  CHECK birthday:   kind <> 'birthday' OR (all_day AND rrule = 'FREQ=YEARLY' AND end_date = start_date)
  INDEX (group_id, window_start)
  INDEX (group_id, window_end)

event_exceptions                            -- MVP: cancels one occurrence
  id                 uuid pk
  event_id           uuid not null -> events CASCADE
  occurrence_key     varchar(20) not null   -- '20261001T160000Z' (timed) | '20261001' (all-day)
  created_by_id      uuid null -> users SET NULL
  created_at
  UNIQUE (event_id, occurrence_key)
  -- later: override_* columns for single-occurrence edits

polls
  id                 uuid pk
  group_id           uuid not null -> groups CASCADE        -- copied from the activity
  activity_id        uuid not null -> activities CASCADE  (idx)
  question           varchar(200) not null
  allow_multiple     bool not null default false   -- fixed at creation
  closes_at          ts null                -- automatic close
  closed_at          ts null                -- manual close
  created_by_id      uuid null -> users SET NULL
  created_at, updated_at
  -- cut from the MVP: is_anonymous, max_choices, allow_member_options (any member may add options)

poll_options
  id                 uuid pk
  poll_id            uuid not null -> polls CASCADE
  label              varchar(100) not null COLLATE NOCASE
  url                varchar(2048) null
  position           int not null
  added_by_id        uuid null -> users SET NULL
  created_at
  UNIQUE (poll_id, label)

poll_votes
  option_id          uuid not null -> poll_options CASCADE
  user_id            uuid not null -> users CASCADE
  poll_id            uuid not null -> polls CASCADE   -- denormalized for per-poll queries
  created_at
  PK (option_id, user_id)
  INDEX (poll_id, user_id)

wheel_spins
  id                 uuid pk
  group_id           uuid not null -> groups CASCADE
  spun_by_id         uuid null -> users SET NULL
  filters            json not null          -- WheelFilters as sent, after normalization
  candidates         json not null          -- snapshot [{id, title, category_id, color}] in slice order, 2..50
  result_index       int not null           -- index into candidates
  result_activity_id uuid null -> activities SET NULL  -- = candidates[result_index].id while it exists
  accepted_at        ts null
  accepted_by_id     uuid null -> users SET NULL
  created_at                                -- no updated_at column is needed; accepted_* are write-once
  INDEX (group_id, created_at)

group_log                                   -- append-only domain events (section 3.2)
  id                 uuid pk                -- UUIDv7, so ordering by id = ordering by time
  group_id           uuid not null -> groups CASCADE
  actor_id           uuid null -> users SET NULL
  action             varchar(40) not null
  subject_type       varchar(20) null       -- group | member | invite | category | activity | event | poll | spin
  subject_id         uuid null              -- no FK: the subject may be deleted later
  data               json not null default '{}'
  created_at
  INDEX (group_id, created_at)
  INDEX (group_id, action, created_at)
```

Deletion effects that follow from the foreign keys and the services:
- **Deleting a group** removes everything in it: memberships, invites, categories, activities,
  events, polls, spins and log rows.
- **Deleting an activity** removes its interests and its polls (with their options and votes).
  Linked events stay: the service sets their `activity_id = null` and increments their `version`
  (section 1.7; the FK's `SET NULL` is only a safety net). Spins keep their snapshots, with
  `result_activity_id = null`.
- **Deleting a category** is covered in section 8.6.

### 3.2 `group_log` actions

A row is written in the **same transaction** as the change, by the service layer. The MVP has no UI
or endpoint for it; the recap and notifications will build on it. For `member.*` actions,
`subject_id` is the user's ID.

| action | subject_type | data |
|---|---|---|
| `group.created` | group | `{}` |
| `group.updated` | group | `{"fields": ["name", …]}` |
| `group.ownership_transferred` | member | `{"from": uuid, "to": uuid}` |
| `member.joined` | member | `{"via": "create" \| "invite" \| "register", "invite_id": uuid \| null}` |
| `member.left` | member | `{"reason": "left" \| "account_deleted"}` |
| `member.removed` | member | `{}` |
| `member.role_changed` | member | `{"from": role, "to": role}` |
| `member.settings_updated` | member | `{"show_birthday": bool}` |
| `invite.created`, `invite.revoked` | invite | `{"max_uses": int \| null, "expires_at": str \| null}` / `{}` |
| `category.created`, `category.updated`, `category.deleted` | category | `{"name": str}` |
| `activity.created` | activity | `{"title": str, "category_id": uuid \| null, "status": str}` |
| `activity.updated` | activity | `{"fields": [...]}` |
| `activity.status_changed` | activity | `{"from": status, "to": status, "via": "status" \| "event" \| "wheel"}` |
| `activity.deleted` | activity | `{"title": str}` |
| `activity.interest_added`, `activity.interest_removed` | activity | `{}` |
| `event.created`, `event.updated`, `event.deleted` | event | `{"title": str, "kind": str}` |
| `event.occurrence_cancelled`, `event.occurrence_restored` | event | `{"occurrence_key": str}` |
| `poll.created`, `poll.updated`, `poll.closed`, `poll.reopened`, `poll.deleted` | poll | `{"activity_id": uuid, "question": str}` |
| `poll.option_added`, `poll.option_deleted` | poll | `{"option_id": uuid, "label": str}` |
| `poll.voted` | poll | `{"option_ids": [uuid, …]}` |
| `wheel.spun` | spin | `{"result_activity_id": uuid, "candidate_count": int}` |
| `wheel.accepted` | spin | `{"activity_id": uuid}` |

---

## 4. Auth mechanics

### 4.1 Access token

- A JWT signed **HS256** with `JWT_SECRET`. There is no `jti`, and validation allows **30 s of clock
  leeway**.

| Claim | Value |
|---|---|
| `sub` | user ID (UUID string) |
| `sid` | refresh-token `family_id` of the session (UUID string) |
| `tv` | `users.token_version` when the token was issued |
| `typ` | `"access"` |
| `iat` | issue time (integer seconds) |
| `exp` | `iat + ACCESS_TOKEN_TTL_MINUTES*60` (default 900 s) |
| `iss` | `"friends-api"` |
| `aud` | `"friends-app"` |

- `get_current_user` runs on every authenticated request:
  1. A missing or non-Bearer header, a malformed token, a bad signature, or a wrong `iss`, `aud` or
     `typ` → 401 `unauthenticated`.
  2. `exp` passed (beyond the leeway) → 401 `token_expired`.
  3. It loads the user. If the user doesn't exist, `deleted_at` is set, or `tv != token_version`
     → 401 `unauthenticated`.
- Access tokens aren't checked against their refresh family. After a single-session logout, an access
  token stays valid for at most 15 minutes, which is accepted. The client discards it.

### 4.2 Passwords

- argon2-cffi **25.1, used directly** (no pwdlib): `PasswordHasher(time_cost, memory_cost,
  parallelism)`, with the parameters from settings.
- Every hash and verify call runs inside a `threading.BoundedSemaphore(2)`, which bounds memory use on
  the Pi.
- For an unknown or deleted email, the password is verified against a module-level dummy hash, so the
  timing doesn't reveal whether the account exists. The response is 401 `invalid_credentials`.
- After a successful login, `check_needs_rehash` runs; if it is true, the new hash is stored.
- Rules: 10..128 code points (422 `validation_error` on the field), and not equal to the email
  (case-insensitive; 422 `weak_password`, section 2). No composition rules.

### 4.3 Register (`POST /auth/register`)

1. The `register` rate-limit bucket (section 4.9).
2. The body is validated. The email is normalized. An invalid `timezone` becomes `UTC`; `null` also
   means `UTC`.
3. With `REGISTRATION_MODE=invite_only` and `invite_code` null → **403 `registration_closed`**.
4. If `invite_code` is given (in either mode), it is normalized (section 4.7):
   - unknown or malformed → 404 `not_found`;
   - otherwise the invite status is checked: 410 `invite_revoked`, `invite_expired` or
     `invite_exhausted`;
   - a group that already has 100 members → 422 `limit_reached`.
5. An email that already exists → 409 `email_taken`. A deleted account's email is free again.
6. In **one transaction**:
   - create the user;
   - if there is an invite: create the membership (`role=member`, `invite_id`), consume one use
     (section 4.7) and log `member.joined {via: "register"}`;
   - create a refresh family (`session_started_at = now`, `device_label`).
7. Return **201 `AuthSession`** with `joined_group` set when an invite was used.

The first account is created with `python -m friends_api.cli create-user`. That user creates a group
and invites everyone else.

### 4.4 Login (`POST /auth/login`)

1. The `login` bucket (10/min/IP). Normalize the email.
2. Unknown email, a deleted user, or a wrong password → **401 `invalid_credentials`**, after a dummy
   verify for unknown users.
3. On success: rehash if needed, set `last_login_at = now`, and start a new family
   (`session_started_at = now`, `device_label`).
4. Return 200 `AuthSession` with `joined_group = null`.

### 4.5 Refresh (`POST /auth/refresh`): rotation with a 60-second grace

Hash the presented token with SHA-256 and look it up:
1. Not found → 401 `refresh_invalid`.
2. `revoked_at` is set, or the user is deleted → 401 `refresh_invalid`.
3. `used_at` is set, so this is reuse:
   - **Grace re-issue:** if `now - used_at <= REFRESH_REUSE_GRACE_SECONDS` (60) **and** the successor
     (`replaced_by_id`) has `used_at IS NULL` and `revoked_at IS NULL`: revoke that successor
     (`revoked_at = now`), issue a new token in the same family, point the presented token's
     `replaced_by_id` at it, and return **200 `TokenPair`**. This handles a lost response and two tabs
     refreshing at once.
   - Otherwise revoke every token in the family and return **401 `refresh_reuse_detected`**.
4. `expires_at <= now` → 401 `refresh_invalid`.
5. **Normal rotation:**
   - set `used_at = now` on the presented token;
   - insert a successor with the same `family_id`, `session_started_at` and `device_label`, and
     `expires_at = min(now + 30 d, session_started_at + 180 d)`;
   - if that minimum is already `<= now`, the session cap is reached → 401 `refresh_invalid`;
   - set `replaced_by_id`, and return 200 `TokenPair` with a new access token (`sid` = family,
     `tv` = the current `token_version`).

The client runs **one refresh at a time** (a single-flight `QueuedInterceptorsWrapper`) and re-reads the
stored refresh token just before refreshing. The server grace covers what is left, so there is no
cross-tab lock.

### 4.6 Logout, logout-all, password change

- **`POST /auth/logout {refresh_token}`** is **public and idempotent**. If the token is found, every
  token in its family gets `revoked_at = now`. It **always returns 204**, including for unknown,
  used or revoked tokens. It works even when the access token is dead.
- **`POST /auth/logout-all`** (authenticated): `token_version += 1` and every refresh token of the
  user is revoked. The caller's access token dies immediately. Returns 204.
- **`POST /me/password {current_password, new_password}`**:
  1. A wrong current password → 422 `wrong_password` (`errors[0].field = "current_password"`).
  2. Otherwise: store the new hash, `token_version += 1`, and revoke every refresh token of the user.
     That includes the caller's family, whose active token is revoked, not marked used.
  3. Start a new family for the caller, with the old `session_started_at` and `device_label`.
  4. Return **200 `TokenPair`**. The current device stays signed in and every other session ends.

### 4.7 Invite codes

- **Alphabet:** Crockford base32, `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no I, L, O or U).
- **Generation:** 10 characters from `secrets.choice` (about 50 bits), retried on a unique-index
  collision.
- **Link:** `{PUBLIC_APP_URL}/join/{code}`. Clients may display the code as `XXXXX-XXXXX`.
- **Normalization,** done by the server on every input (path parameter or `RegisterRequest.invite_code`)
  and mirrored by the client:
  1. remove whitespace and `-`;
  2. uppercase;
  3. map `I`→`1`, `L`→`1`, `O`→`0`.

  The result must match `^[0-9A-HJKMNP-TV-Z]{10}$`, otherwise the response is 404 `not_found`. For
  example, `abcd-efgh-ik` becomes `ABCDEFGH1K`, and ` abcde fghjk ` becomes `ABCDEFGHJK`.
- **Status** is computed on read. When several apply, the first wins:
  1. `revoked_at` set → `revoked`;
  2. `expires_at <= now` → `expired`;
  3. `max_uses` set and `use_count >= max_uses` → `exhausted`;
  4. otherwise → `valid`.
- **Consuming a use** (accept, or register with a code) is one conditional statement:
  `UPDATE invites SET use_count = use_count + 1, updated_at = :now WHERE id = :id AND revoked_at IS
  NULL AND (expires_at IS NULL OR expires_at > :now) AND (max_uses IS NULL OR use_count < max_uses)`.
  If it updates no row, the invite is re-read and the matching 410 is returned. Two concurrent accepts
  on a `max_uses=1` invite produce exactly one join.
- **Accepting** when the caller is already a member returns 200 `Group` and consumes no use, whatever
  the invite's status.

### 4.8 Account deletion (`POST /me/deletion {password}`)

A wrong password → 422 `wrong_password`. Otherwise, in **one transaction**:

1. **Ownership.** For every group the user owns:
   - if there are other members, ownership goes to the **oldest admin** (by `joined_at`), otherwise to
     the **oldest member**; log `group.ownership_transferred`;
   - if the user is the sole member, **delete the group**.
2. **Membership end** (section 7.5) for every remaining membership, with reason `account_deleted`.
3. **Anonymize** the user row:
   - `email = 'deleted-<id>@invalid'` (frees the address);
   - `password_hash = null`, `display_name = 'Deleted user'`;
   - `avatar_url`, `birthday_*` and `locale` set to null, `timezone = 'UTC'`;
   - `deleted_at = now`, `token_version += 1`.
4. **Delete all the user's refresh tokens.**
5. **Authored content stays** (activities, events, polls, options, spins, log rows); it shows as
   "Deleted user". Interests and votes are removed by step 2. Invites the user created stay valid until
   an admin revokes them.

Returns 204. Apple requires in-app account deletion; the profile screen offers it.

### 4.9 Rate limits

- In-process sliding window: a dict of deques behind a `threading.Lock`, pruned regularly.
- Keyed by client IP. That is `request.client.host`, made correct by uvicorn `--proxy-headers` with
  `FORWARDED_ALLOW_IPS`.
- `RATE_LIMIT_ENABLED=false` turns it off (the tests do, except in the 429 tests).

| Bucket | Endpoints | Limit |
|---|---|---|
| `login` | `POST /auth/login` | 10 per minute per IP |
| `register` | `POST /auth/register` | 5 per hour per IP |
| `refresh` | `POST /auth/refresh` | 30 per minute per IP |
| `invites` | `GET /invites/{code}`, `POST /invites/{code}/accept` (shared) | 20 per minute per IP |

Over the limit → 429 `rate_limited` with `Retry-After` (integer seconds until a slot frees up).
`/health` is never rate-limited. There is no per-email failure bucket.

### 4.10 Secrets and startup checks

- `JWT_SECRET` comes only from the environment. When `APP_ENV=prod`, startup fails if it is missing,
  shorter than 32 bytes, or equal to the dev placeholder. Generate one with
  `python -c "import secrets;print(secrets.token_urlsafe(48))"`.
- Rotating the secret only invalidates access tokens (at most 15 minutes old). Refresh tokens are
  database rows, so users stay signed in. That makes rotation a safe emergency lever.
- In prod, startup also fails without `PUBLIC_APP_URL`.

---

## 5. Recurrence and birthdays

Pure functions live in `backend/friends_api/features/events/recurrence.py`. They have no database or
FastAPI imports, so the future notification scheduler can reuse them:
- `canonicalize_rrule(raw, start_local_date, all_day, starts_at_utc) -> str`, which raises
  `InvalidRRule(reason)`;
- `expand(...)` and `birthday_dates(...)`.

The client mirrors section 5.2 in `app/lib/features/calendar/domain/rrule_spec.dart`. **Both are
table-tested against `docs/api/rrule_cases.json`.**

### 5.1 Allowed subset

| Part | Allowed |
|---|---|
| `FREQ` | required: `DAILY`, `WEEKLY`, `MONTHLY` or `YEARLY` |
| `INTERVAL` | 1..99 (omitted from the canonical form when it is 1) |
| `BYDAY` | WEEKLY: a list of distinct `MO TU WE TH FR SA SU`. MONTHLY: exactly **one** ordinal weekday, with ordinal `1`–`4` or `-1` (`2TU`, `-1FR`). Not allowed with DAILY or YEARLY. |
| `BYMONTHDAY` | MONTHLY only, a single value `1`–`28` or `-1`, and not together with `BYDAY` |
| `COUNT` | 1..730 |
| `UNTIL` | timed events: `YYYYMMDDTHHMMSSZ` (UTC); all-day events: `YYYYMMDD`; inclusive |
| everything else | rejected: `BYSETPOS`, `BYHOUR`, `BYMINUTE`, `BYSECOND`, `BYMONTH`, `BYWEEKNO`, `BYYEARDAY`, `WKST`, `DTSTART`, `RDATE`, `EXDATE`, … |

- At most one of `COUNT` and `UNTIL`.
- **Weeks start on Monday** (the RFC default, used by `INTERVAL>1` weekly rules).

### 5.2 Parsing, validation and canonical form

The **start** is the event's local start date: `starts_at` converted to `timezone` for timed events,
or `start_date` for all-day events. Steps, in order. The first failure wins, and its reason becomes
`errors[0].type`:

| # | Step | Reason on failure |
|---|---|---|
| 1 | Trim. If the text contains a line break or `DTSTART` (case-insensitive) → reject. Strip an optional leading `RRULE:`, then uppercase. | `embedded_dtstart` |
| 2 | Split on `;`. Each part must be `NAME=VALUE` with both sides non-empty (so `;;` and a trailing `;` are rejected). Parts are checked left to right for this step and the next two. | `syntax` |
| 3 | `NAME` must be one of `FREQ INTERVAL BYDAY BYMONTHDAY COUNT UNTIL`. | `unsupported_part` |
| 4 | No name may repeat. | `duplicate_part` |
| 5 | `FREQ` is present. | `missing_freq` |
| 6 | `FREQ` is one of the four allowed values. | `unsupported_freq` |
| 7 | `INTERVAL` is 1–3 decimal digits with value 1..99. | `interval_out_of_range` |
| 8 | `BYDAY` matches the rules for its FREQ (section 5.1). | `byday_invalid` |
| 9 | `BYMONTHDAY` is MONTHLY-only, a single value in 1..28 or -1, with no `BYDAY`. | `bymonthday_invalid` |
| 10 | Defaults. WEEKLY without `BYDAY` → add the start's weekday. MONTHLY with neither `BYDAY` nor `BYMONTHDAY` → if the start day is after the 28th, reject; otherwise add `BYMONTHDAY=<start day>`. | `monthly_day_over_28` |
| 11 | YEARLY (for `kind=recurring`) starting on 29 February → reject. It would silently skip three years out of four. Birthdays use their own rule (section 5.7). | `yearly_feb29` |
| 12 | Not both `COUNT` and `UNTIL`. | `count_and_until` |
| 13 | `COUNT` is 1–4 decimal digits with value 1..730. | `count_out_of_range` |
| 14 | `UNTIL` has the format for the event type (a UTC `…T……Z` date-time for timed events, `YYYYMMDD` for all-day) and is a real date. | `until_format` |
| 15 | `UNTIL` is not before the start: the instant for timed events (`UNTIL >= starts_at`), the date for all-day (`UNTIL >= start_date`). | `until_before_start` |

- **Canonical form:** `FREQ;INTERVAL (omitted when 1);BYDAY;BYMONTHDAY;COUNT|UNTIL`, uppercase.
  - Weekly `BYDAY` days are sorted `MO..SU`.
  - Numbers are written without leading zeros (`INTERVAL=02` becomes `INTERVAL=2`).
  - `UNTIL` is kept as given.
  - The canonical form is a fixed point: canonicalizing it again gives the same string.
- Examples: `BYDAY=TH;FREQ=WEEKLY` → `FREQ=WEEKLY;BYDAY=TH`. `FREQ=MONTHLY` starting on the 15th →
  `FREQ=MONTHLY;BYMONTHDAY=15`. `rrule:freq=weekly;byday=we,mo` → `FREQ=WEEKLY;BYDAY=MO,WE`.
- Only the canonical form is stored and returned.
- An error returns 422 `invalid_rrule` with
  `errors = [{field: "rrule", message, type: <reason>}]`.
- **The start doesn't have to match the rule.** Occurrences are the rule's matches on or after the
  start (dateutil semantics), so the start is itself an occurrence only if it matches. Example: weekly
  `TU,TH` starting on a Wednesday gives its first occurrence on Thursday.

### 5.3 Expansion

- **Timed events** are expanded in the event's wall clock, with `python-dateutil`:
  - `dtstart = starts_at.astimezone(ZoneInfo(timezone))` (aware), and
    `rule = rrulestr(canonical, dtstart=dtstart)`;
  - `duration = ends_at - starts_at` (an absolute timedelta);
  - occurrence starts are `rule.between(range_start_local - duration, range_end_local, inc=True)`,
    each converted to UTC; each end is start + duration.
  - Wall time is preserved across DST: a weekly Thursday event at 19:00 Europe/Bucharest is
    `16:00Z` until 22 October 2026 and `17:00Z` from 29 October.
  - A wall time inside the spring-forward gap resolves with PEP 495 `fold=0`, using the offset before
    the transition. So 03:30 on 2027-03-28 becomes `01:30Z`, shown as 04:30 local.
  - An ambiguous autumn time uses the first instance (summer time): 03:30 on 2026-10-25 becomes
    `00:30Z`.
- **All-day events** are expanded as naive dates: `dtstart = datetime.combine(start_date, time())`.
  Each occurrence date `d` spans `d .. d + (end_date - start_date)`, inclusive.
- **`one_time`** events have exactly one occurrence. **`birthday`** events use `birthday_dates`
  (section 5.7), not `rrule`.
- Occurrences whose key is in `event_exceptions` are dropped.
- At most 1000 occurrences per event per request.

### 5.4 Search window (written on every event write)

| Event | `window_start` | `window_end` |
|---|---|---|
| timed `one_time` | `starts_at` | `ends_at` |
| timed `recurring`, open-ended | `starts_at` | `null` |
| timed `recurring` with `UNTIL` | `starts_at` | `UNTIL + duration` |
| timed `recurring` with `COUNT` | `starts_at` | last occurrence start + duration (expanded once at write; at most 730) |
| all-day `one_time` | `start_date 00:00Z - 14 h` | `(end_date + 1 day) 00:00Z + 14 h` |
| all-day `recurring`, open-ended | `start_date 00:00Z - 14 h` | `null` |
| all-day `recurring` with `UNTIL` | `start_date 00:00Z - 14 h` | `(UNTIL + span + 1 day) 00:00Z + 14 h` |
| all-day `recurring` with `COUNT` | `start_date 00:00Z - 14 h` | `(last occurrence end date + 1 day) 00:00Z + 14 h` |
| `birthday` | `start_date 00:00Z - 14 h` | `null` |

- The ±14 h widening makes floating dates safe for any viewer timezone.
- The SQL prefilter is `window_start < :range_end_utc AND (window_end IS NULL OR window_end >
  :range_start_utc)`, a superset. Exact filtering then happens in Python.

### 5.5 Calendar queries

- **Endpoints:** `GET /groups/{group_id}/calendar` and `GET /me/calendar`, which covers all my
  groups.
- **Parameters:**
  - `from`, `to`: `ApiDate`; **`to` is exclusive**;
  - `tz`: IANA, defaults to `users.timezone`; an invalid value falls back to `users.timezone`;
  - `kinds`: repeated, any of `one_time`, `recurring`, `birthday`; default all;
  - `category_id` (group calendar only): matches that category **and its subcategories**. When it is
    set, member birthdays are excluded.
- **Validation:** `to <= from` → 422 `validation_error`; `to - from > 400 days` → 422
  `range_too_large`.
- **Range:** `range_start = from 00:00` in `tz` and `range_end = to 00:00` in `tz`, both converted to
  UTC.
- **Inclusion:**
  - a timed occurrence is included when `start < range_end AND end > range_start` (overlap);
  - an all-day occurrence is included when `start_date < to AND end_date >= from`.
- **`kinds=birthday`** covers both `kind=birthday` events and member birthdays, which have
  `kind=birthday` and `source=member_birthday`.
- **Sort order:**
  1. local start date in `tz` (`start_date` for all-day, the date of `starts_at` in `tz` for timed);
  2. all-day before timed;
  3. start instant;
  4. `title`;
  5. `occurrence_key`.
- **Color:** `Occurrence.color` is the event's category's **effective color**, meaning its own color,
  or the parent's for a subcategory with none. It is `null` when there is no category. Member
  birthdays have `color = null`, and the client draws them with its fixed birthday color and a cake
  icon.
- **Timezone labels:** `Occurrence.timezone` is the event's zone. The MVP UI shows times in device-local
  time **without a timezone label**.
- **Scope of `/me/calendar`:**
  - events from all my groups, each with its `group_id`;
  - member birthdays **de-duplicated per user**: included if `show_birthday` is on in at least one
    group we share, with `group_id = null`;
  - no `category_id` parameter.

### 5.6 Occurrence keys and exceptions

- **Keys:**
  - timed: the occurrence's originally scheduled start in UTC, `YYYYMMDDTHHMMSSZ`
    (e.g. `20261029T170000Z`);
  - all-day and birthdays: `YYYYMMDD`.
  - A client identifies an occurrence by `(event_id or user_id, occurrence_key)`.
- **Cancel:** `DELETE /events/{event_id}/occurrences/{key}` inserts an exception.
  - It is idempotent (204).
  - The key must be a real occurrence of the series: for timed events, the rule yields exactly that
    instant; for all-day and birthday events, that date is an occurrence date. Otherwise → 404
    `not_found`.
  - A malformed key → 422 `validation_error` (`path.occurrence_key`).
  - A `one_time` event → 422 `validation_error` (delete the event instead).
- **Restore:** `POST /events/{event_id}/occurrences/{key}/restore` deletes the exception. It is
  idempotent (204, even when there was no exception).
- `Event.cancelled_occurrence_keys` lists the exceptions, sorted.
- A PUT that changes `starts_at`, `start_date`, `all_day`, `timezone` or `rrule` **deletes every
  exception** of the event, because they refer to the old occurrences. Changing only the end time or
  duration keeps them.

### 5.7 Birthdays

Both kinds of birthday use one function:
`birthday_dates(month, day, first_year | None, from, to)`. For each year Y in the range, the date is
`(Y, month, day)`, except that **29 February becomes 28 February in non-leap years**. A date is
included if `from <= date < to` and (`first_year` is null or `Y >= first_year`). Birthdays never use
`rrule`.

1. **Member birthdays** come from profiles as virtual occurrences, with no event rows.
   - Included for each current member of the group with `show_birthday = true`, a birthday set, and
     not deleted.
   - Occurrence fields:
     - `source = member_birthday`, `event_id = null`, `user_id` set;
     - `kind = birthday`, `title = <display_name>` (the client adds "'s birthday");
     - `all_day = true`, `start_date = end_date`, `timezone = null`;
     - `category_id = null`, `color = null`, `activity_id = null`;
     - `is_recurring = true`, `can_edit = false`, `occurrence_key = YYYYMMDD`.
   - The birth year is never exposed to others.
2. **`kind=birthday` events** are for people who aren't on the app.
   - `title` is the person's name; `first_year = start_date.year`.
   - They are all-day with `rrule = 'FREQ=YEARLY'` and `end_date = start_date`, which the server
     enforces (section 5.8).
   - 29 February is allowed as the start.
   - They can have a category, and single occurrences can be cancelled.

### 5.8 Event write rules (`EventWrite`)

- **By kind:**
  - `one_time`: `rrule` must be null.
  - `recurring`: `rrule` is required; it is canonicalized (section 5.2) and stored canonical.
  - `birthday`:
    - `all_day` must be true and `start_date` is required;
    - `starts_at` and `ends_at` must be null;
    - `end_date` must be null or equal to `start_date`;
    - `rrule` must be null or equal to `FREQ=YEARLY` after trimming, uppercasing and removing an
      optional `RRULE:` prefix. It is **not** run through section 5.2, so `yearly_feb29` doesn't
      apply and a 29 February birthday is accepted;
    - the server stores `rrule='FREQ=YEARLY'` and `end_date=start_date`.
- **By timing:**
  - `all_day = true` (`one_time`/`recurring`): `start_date` is required; `end_date` null means
    `start_date`; `end_date >= start_date`; `starts_at` and `ends_at` must be null.
  - `all_day = false`: `starts_at` and `ends_at` are required (aware) with `ends_at > starts_at`;
    `start_date` and `end_date` must be null.
- **Other fields:**
  - Duration is at most 30 days (timed: `ends_at - starts_at`; all-day: `end_date - start_date + 1`).
  - `timezone`: IANA; null means the group's timezone.
  - `category_id` and `activity_id` must belong to the same group (422 `invalid_reference`).
- **Scheduling side effect:** when an event is created with an `activity_id`, or a PUT links a
  different activity, and that activity's status is `idea` or `planning`, the status becomes
  **`scheduled`**. That sets `status_changed_at` and logs
  `activity.status_changed {via: "event"}`. Deleting or unlinking an event never changes the status.
- `ActivitySummary.next_occurrence` is the first occurrence that hasn't ended, across events linked
  to the activity. Timed: `end > now`. All-day: `end_date >= today` in the group's timezone.

### 5.9 Shared fixtures (`docs/api/rrule_cases.json`)

- **`valid[]`:**
  - `input` must canonicalize to `canonical`;
  - expanding with `dtstart_local`, `all_day` and `tz` over `range` (start-in-range semantics,
    duration 0) must give `expected_local`, and `expected_utc` for timed cases.
- **`invalid[]`:** each `input` (with `start_date` and `all_day`) must be rejected with the given
  `reason`. Each invalid case has exactly one defect.
- **`birthdays[]`:** exercises `birthday_dates`.
- **Consumers:** pytest (`backend/tests/unit/test_recurrence.py`) runs everything. The Dart
  `rrule_spec` tests run `valid[].input → canonical` and `invalid[]`; the client never expands timed
  rules.

---

## 6. Custom fields per category

This lets a "Movie night" item have a genre, an IMDb rating, an IMDb link and a year. Definitions live
in `categories.field_defs`. Values live in `activities.attributes`. **All validation is in the service
layer.** In OpenAPI, `attributes` is a free-form object (`dict[str, Any]`).

### 6.1 `FieldDef`

```
FieldDef {
  key: str            # ^[a-z][a-z0-9_]{0,29}$ ; unique within the category's effective defs
  label: str          # 1..40
  type: FieldType     # text | long_text | number | rating | url | select | year
  options: str[]?     # select only (required): 1..30 items, each 1..40, unique case-insensitively; null for other types
  min: float?         # number and rating only; null otherwise
  max: float?         # number and rating only; min < max when both set
  show_on_card: bool = false
}
```
- A category has **at most 12** of its own `field_defs`. The list order is the display order.
- **Rating:** `min` and `max` must lie within 0..10. When omitted they mean 0 and 10.
- **Year:** has a fixed range of 1800..2200, and `min`/`max` must be null.
- Shape errors (regex, lengths, counts, options on a non-select type, min/max on the wrong type,
  `min >= max`, duplicate keys in one list) → 422 `validation_error`, with fields like
  `field_defs.2.key`.

### 6.2 Category-level rules

- **Effective definitions:**
  - for a top-level category, its own `field_defs`;
  - for a subcategory, **the parent's `field_defs` followed by its own**;
  - an uncategorized activity has none.
  - `Category.effective_field_defs` returns them, and the client's `DynamicFieldsForm` renders them.
- **Keys are unique across a parent and its subcategories.** Each of these gets 422
  `field_key_conflict`:
  - saving a subcategory whose key exists in the parent;
  - saving a parent with a new key that exists in any of its subcategories;
  - moving a subcategory under a parent where a key clashes.
- **No type changes.** A PUT that gives an existing key (present in the category's stored
  `field_defs`) a different `type` → 422 `field_type_change`. To change a type, remove the field in
  one PUT and add it back in another.
- Other edits are allowed: labels, options, min/max, `show_on_card`, order, adding and removing.
  Values that no longer validate are hidden on read (section 6.4).

### 6.3 Attribute values (`activities.attributes`)

The request body is `attributes: {key: value}`. **`null` or an empty string clears a key.** Stored JSON
never contains nulls.

| type | JSON value | Rule | errors[].type on failure |
|---|---|---|---|
| `text` | string | 1..200 characters | `wrong_type`, `too_long` |
| `long_text` | string | 1..5000 characters | `wrong_type`, `too_long` |
| `number` | number (int or float; **not bool**) | finite; `min <= v <= max` when set | `wrong_type`, `out_of_range` |
| `rating` | number (not bool) | `min..max` (default 0..10), **at most one decimal** (`round(v*10) == v*10`) | `wrong_type`, `out_of_range`, `too_many_decimals` |
| `url` | string | absolute http/https URL, at most 2048 characters | `wrong_type`, `invalid_url` |
| `select` | string | exactly one of `options` (exact, case-sensitive match) | `wrong_type`, `not_an_option` |
| `year` | integer (not bool, not a float) | 1800..2200 | `wrong_type`, `out_of_range` |
| any key not in the effective defs | – | – | `unknown_key` |

- **All** failing keys are reported in one 422 `invalid_attributes`, as
  `errors = [{field: "attributes.<key>", message, type}]`.
- Python's `bool` is a subclass of `int`, so booleans are rejected explicitly.

### 6.4 Write and read semantics

- **Create:** `attributes` is validated strictly against the effective defs of `category_id`.
- **Update (PUT):** the body's `attributes` **replaces** the stored object.
  - **Category change:** if `category_id` differs from the stored one, keys that exist in the **old**
    category's effective defs but not in the new one are **dropped silently** before validation. The
    client warns first. Any other unknown key still gets `unknown_key`.
- **Read:** the stored values are filtered on the fly.
  - A key is returned only if it is in the current effective defs **and** its stored value still
    passes section 6.3 for the current definition (type, options, range).
  - So values for deleted fields, and stale values after a field was removed and re-added with another
    type, are **ignored on read**. They are removed by the next PUT, since the client sends back what
    it received. GET never writes.
- **`ActivitySummary.card_attributes`** holds the returned attributes whose def has
  `show_on_card = true`, in effective-def order, as `[{key, label, type, value}]`. For example, the
  IMDb rating on a movie card.
- Filtering the backlog or the wheel by attribute is out of scope for the MVP (section 11).

### 6.5 Default categories (seeded when a group is created with `seed_default_categories=true`)

All are top-level. `created_by` is the group creator, and positions are 0..6 in this order. Each one
is logged as `category.created` by the creator, after `group.created` and `member.joined`:

| position | name | color | icon | field_defs |
|---|---|---|---|---|
| 0 | Movie night | `#7E57C2` | `movie` | see below |
| 1 | Food & drinks | `#EF6C00` | `food` | `[]` |
| 2 | Outdoors | `#2E7D32` | `outdoors` | `[]` |
| 3 | Games | `#1565C0` | `games` | `[]` |
| 4 | Trips | `#00838F` | `trips` | `[]` |
| 5 | Culture | `#AD1457` | `culture` | `[]` |
| 6 | Sports | `#C62828` | `sports` | `[]` |

Movie night `field_defs`, exactly:
```json
[
  {"key": "genre", "label": "Genre", "type": "select",
   "options": ["Action", "Comedy", "Drama", "Horror", "Sci-fi", "Animation", "Documentary", "Thriller", "Romance", "Other"],
   "min": null, "max": null, "show_on_card": false},
  {"key": "imdb_rating", "label": "IMDb rating", "type": "rating", "options": null, "min": 0, "max": 10, "show_on_card": true},
  {"key": "imdb_url", "label": "IMDb link", "type": "url", "options": null, "min": null, "max": null, "show_on_card": false},
  {"key": "year", "label": "Year", "type": "year", "options": null, "min": null, "max": null, "show_on_card": false},
  {"key": "runtime_min", "label": "Runtime (min)", "type": "number", "options": null, "min": 1, "max": 600, "show_on_card": false}
]
```
- A movie's short description is the activity's normal `description`.
- Subcategories (such as genre buckets) are optional, and none are seeded.
- Auto-filling from IMDb/OMDb/TMDB is out of scope.
- **Icon keys** known to the app: `movie, food, outdoors, games, trips, culture, sports, music, party,
  home, star`. The server only checks the length (40 or fewer). Unknown keys and emojis are shown as
  given, or as a default icon.

---

## 7. Authorization matrix

### 7.1 Membership resolution (loader dependencies)

- **Collection routes** (`/groups/{group_id}/...`) use `load_group`. It returns `(Group, Membership)`.
- **Flat item routes** use loaders that load the entity, then the caller's membership in
  `entity.group_id`, and return `(entity, Membership)`: `load_activity`, `load_event`, `load_poll`,
  `load_category`, `load_spin`, and `load_invite(group_id, invite_id)`.
- **A missing entity and a non-member caller both give 404 `not_found`**, with identical bodies. This
  hides that a group exists.
- A member without the required role or ownership gets **403 `forbidden`**.
- Permission rules are **policy functions**, for example
  `can_edit_activity(membership, activity) -> bool`. The same functions enforce the rules and compute
  the `can_*` flags in responses, so the UI and the server never disagree.
- IDs referenced in bodies are resolved within the same group; a failure gives 422
  `invalid_reference`. Unknown IDs in **query filters** just match nothing.

### 7.2 Matrix

"Manager" of a poll means its creator, the owner of its activity, or an admin+.

| Capability | member | admin | owner | Notes |
|---|---|---|---|---|
| View group, members, categories, activities, calendar, polls, spins | ✓ | ✓ | ✓ | |
| Edit group settings (`PUT /groups/{id}`) | – | ✓ | ✓ | |
| Delete group, transfer ownership, change roles | – | – | ✓ | Roles assignable: `admin`, `member` |
| Remove a member whose role is `member` | – | ✓ | ✓ | |
| Remove an admin | – | – | ✓ | |
| Leave the group | ✓ | ✓ | only after a transfer (`409 owner_must_transfer`); if sole member, the group is deleted | |
| Create an invite | if `members_can_invite` | ✓ | ✓ | never-expiring invites: admin+ only |
| See invites | own | all | all | |
| Revoke an invite | own | any | any | |
| Create a category | ✓ | ✓ | ✓ | |
| Edit or delete a category (including `field_defs`) | own (creator) | any | any | |
| Create an activity, edit its content (PUT), change its status | ✓ | ✓ | ✓ | version check |
| Change an activity's `owner_id` (in PUT) | claim it if unowned (set to self); the current owner can hand it to anyone or to nobody | any | any | otherwise 403 |
| Delete an activity | if creator or owner | ✓ | ✓ | |
| Toggle interest, vote | self | self | self | |
| Create an event | ✓ | ✓ | ✓ | |
| Edit or delete an event, cancel or restore an occurrence | creator, or the linked activity's owner | ✓ | ✓ | |
| Create a poll, add an option | ✓ | ✓ | ✓ | any member may add options |
| Edit, close, reopen or delete a poll | manager | ✓ | ✓ | |
| Delete a poll option | whoever added it (while it has no votes), or the manager | ✓ | ✓ | |
| Spin the wheel, accept a spin | ✓ | ✓ | ✓ | |
| See a member's birthday (month and day) | if that member's `show_birthday` is on in this group | | | always for yourself |
| Your own profile, password, deletion, calendar | self | self | self | |

### 7.3 `can_*` flags in responses

| Schema | Flags |
|---|---|
| `ActivitySummary` / `Activity` | `can_edit` (true for every member; content is editable by all), `can_delete` |
| `Event` | `can_edit` (also allows cancel/restore), `can_delete` (same value) |
| `Occurrence` | `can_edit` (the event's `can_edit`; always false for member birthdays) |
| `Category` | `can_edit`, `can_delete` (same value), plus `created_by` |
| `Invite` | `can_delete` (revoke) |
| `Poll` | `can_manage` |
| `PollOption` | `can_delete` |

The owner-change rule is derived on the client from `my_role`, `owner` and the caller's ID.

### 7.4 `test_authz_matrix`

It enumerates `app.routes` and, for **every route with a UUID path parameter** (flat routes too), it
calls the route:
1. as an authenticated non-member → expects 404 `not_found`;
2. for routes marked admin, owner, manager or creator above: as a plain member who is neither
   creator nor owner → expects 403 `forbidden`.

Public routes are excluded.

### 7.5 Membership end (leave, remove, account deletion)

In one transaction:
1. Delete the user's `activity_interests` on this group's activities.
2. Delete the user's `poll_votes` on this group's polls.
3. Set `owner_id = null` (with `version + 1`) on this group's activities the user owns.
4. Delete the membership.
5. Log `member.left {reason}` or `member.removed`.

Authored content (`created_by`) is kept.

---

## 8. Endpoints

**Auth column**
- `public`: no token.
- `user`: any signed-in user.
- `member`, `admin+`, `owner`: role in the resource's group.
- `rule`: see section 7.2.
- `RL:<bucket>`: rate-limited (section 4.9).

Bodies and responses are the schemas in section 9. The extra-errors column lists codes beyond the
generic ones in section 2. The operationId equals the handler name, and there is **one tag per
router**.

### 8.1 health (tag `health`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /health` | `get_health` | public (not rate-limited, not access-logged) | – | 200 `Health` (`db: "ok"` after `SELECT 1`); 503 `Health` with `status: "degraded", db: "error"` when the database is unreachable | – |

The Docker HEALTHCHECK calls `http://127.0.0.1:8000/api/v1/health`.

### 8.2 auth (tag `auth`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `POST /auth/register` | `register` | public, RL:register | `RegisterRequest` | 201 `AuthSession` | 403 `registration_closed`; 404 `not_found` (invite); 409 `email_taken`; 410 `invite_*`; 422 `limit_reached`, `weak_password` |
| `POST /auth/login` | `login` | public, RL:login | `LoginRequest` | 200 `AuthSession` | 401 `invalid_credentials` |
| `POST /auth/refresh` | `refresh_tokens` | public, RL:refresh | `RefreshRequest` | 200 `TokenPair` | 401 `refresh_invalid`, `refresh_reuse_detected` |
| `POST /auth/logout` | `logout` | public | `RefreshRequest` | 204 always; revokes the token's family | – |
| `POST /auth/logout-all` | `logout_all` | user | – | 204; `token_version += 1`, all families revoked | – |

### 8.3 users (tag `users`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /me` | `get_me` | user | – | 200 `Me` | – |
| `PUT /me` | `update_me` | user | `MeUpdate` | 200 `Me` | – |
| `POST /me/password` | `change_password` | user | `PasswordChange` | 200 `TokenPair` (section 4.6) | 422 `wrong_password`, `weak_password` |
| `POST /me/deletion` | `delete_account` | user | `AccountDeletion` | 204 (section 4.8) | 422 `wrong_password` |
| `GET /me/calendar` | `get_my_calendar` | user | query `from`, `to`, `tz?`, `kinds*` | 200 `CalendarResponse` across all my groups (section 5.5); endpoint only, no MVP UI | 422 `range_too_large` |

### 8.4 groups (tag `groups`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /groups` | `list_groups` | user | – | 200 `GroupSummary[]` (my groups, by name) | – |
| `POST /groups` | `create_group` | user | `GroupCreate` | 201 `Group`; the caller becomes owner; the default categories are seeded unless `seed_default_categories` is false (section 6.5) | 422 `limit_reached` |
| `GET /groups/{group_id}` | `get_group` | member | – | 200 `Group` | – |
| `PUT /groups/{group_id}` | `update_group` | admin+ | `GroupUpdate` | 200 `Group` | 403 |
| `DELETE /groups/{group_id}` | `delete_group` | owner | – | 204; cascades everything | 403 |
| `POST /groups/{group_id}/transfer-ownership` | `transfer_ownership` | owner | `TransferOwnership` | 200 `Group`; the target becomes owner, the caller becomes admin | 403; 422 `invalid_reference` (not a member), `validation_error` (self) |
| `GET /groups/{group_id}/members` | `list_members` | member | – | 200 `Member[]` (owner, then admins, then members; each by `display_name`) | – |
| `PUT /groups/{group_id}/members/{user_id}/role` | `update_member_role` | owner | `RoleUpdate` | 200 `Member` | 403; 404 (not a member); 409 `owner_must_transfer` (target is the owner) |
| `DELETE /groups/{group_id}/members/{user_id}` | `remove_member` | rule | – | 204. `user_id` = the caller means **leave**. A sole member leaving deletes the group. Runs section 7.5. | 403; 404; 409 `owner_must_transfer` |
| `PUT /groups/{group_id}/members/me/settings` | `update_my_member_settings` | member | `MemberSettingsUpdate` | 200 `Member` | – |

### 8.5 invites (tag `invites`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /groups/{group_id}/invites` | `list_invites` | member | – | 200 `Invite[]`, newest first, at most 100 (section 1.9). Admins+ see all, members see their own. Includes non-valid invites (use `status`). | – |
| `POST /groups/{group_id}/invites` | `create_invite` | member if `members_can_invite`, else admin+ | `InviteCreate` | 201 `Invite` | 403 (invites are off for members, or a member asked for `never_expires`) |
| `DELETE /groups/{group_id}/invites/{invite_id}` | `revoke_invite` | creator or admin+ | – | 204; sets `revoked_at`; idempotent | 403 |
| `GET /invites/{code}` | `preview_invite` | public, RL:invites | – | 200 `InvitePreview` (any status) | 404 (unknown or malformed code) |
| `POST /invites/{code}/accept` | `accept_invite` | user, RL:invites | – | 200 `Group`. Joins as `member`, consumes one use, logs `member.joined {via: "invite"}`. If already a member: 200 and nothing changes. | 404; 410 `invite_*`; 422 `limit_reached` |

### 8.6 categories (tag `categories`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /groups/{group_id}/categories` | `list_categories` | member | – | 200 `CategoryNode[]`. Top-level categories by (`position`, `name`), each with its subcategories in the same order. | – |
| `POST /groups/{group_id}/categories` | `create_category` | member | `CategoryWrite` | 201 `Category` | 409 `name_taken`; 422 `category_depth_exceeded`, `invalid_reference`, `field_key_conflict`, `limit_reached`, `validation_error` (top-level without `color`) |
| `PUT /categories/{category_id}` | `update_category` | creator or admin+ | `CategoryWrite` | 200 `Category` | 403; 409 `name_taken`; 422 `category_depth_exceeded`, `invalid_reference`, `field_key_conflict`, `field_type_change` |
| `DELETE /categories/{category_id}` | `delete_category` | creator or admin+ | – | 204 (see below) | 403 |

Rules for categories:
- **Deleting a subcategory:** its activities and events move to the parent (`version + 1` each).
- **Deleting a top-level category:** its subcategories are deleted too. Activities and events in it or
  in its subcategories become uncategorized (`version + 1`). Each deleted category, subcategories
  included, gets its own `category.deleted` row.
- **Moving with `parent_id` in a PUT:**
  - a category that has subcategories can't get a parent (`category_depth_exceeded`);
  - the parent must be top-level and in the same group;
  - key conflicts are re-checked.
- `position: null` in `CategoryWrite` means "append at the end among siblings" on create and "keep"
  on update.

### 8.7 activities (tag `activities`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /groups/{group_id}/activities` | `list_activities` | member | query (below) | 200 `ActivityPage` | – |
| `POST /groups/{group_id}/activities` | `create_activity` | member | `ActivityCreate` | 201 `Activity`. The creator is marked interested. `owner_id` may name any current member; `null` means the creator. `status_changed_at = now`; `completed_at = now` if created as `done`. | 422 `invalid_reference`, `invalid_attributes` |
| `GET /activities/{activity_id}` | `get_activity` | member | – | 200 `Activity` | – |
| `PUT /activities/{activity_id}` | `update_activity` | member (an owner change follows the rule) | `ActivityUpdate` | 200 `Activity`. `owner_id = null` means unowned. | 403 (owner change); 409 `version_conflict`; 422 `invalid_reference`, `invalid_attributes` |
| `DELETE /activities/{activity_id}` | `delete_activity` | creator, owner or admin+ | – | 204 (section 3.1 deletion effects) | 403 |
| `POST /activities/{activity_id}/status` | `set_activity_status` | member | `StatusChange` | 200 `Activity`. Any transition is allowed. On a real change: `status_changed_at = now`; `completed_at = now` on entering `done`, `null` on leaving it; logged with `via: "status"`. The same status is a no-op. | – |
| `PUT /activities/{activity_id}/interest` | `add_interest` | member | – | 200 `InterestState` (idempotent) | – |
| `DELETE /activities/{activity_id}/interest` | `remove_interest` | member | – | 200 `InterestState` (idempotent) | – |

**`list_activities` query parameters.** `WheelFilters` (section 10) uses the same filter semantics.

| Param | Type | Default | Meaning |
|---|---|---|---|
| `status` | `ActivityStatus`, repeated | `idea`, `planning`, `scheduled` | done/dropped are the archive; the client's "Show archived" adds them |
| `category_id` | uuid | – | activities in that category |
| `include_subcategories` | bool | `true` | with `category_id`: also its subcategories |
| `owner_id` | uuid | – | owned by that member ("Mine") |
| `interested_by` | uuid | – | that member is interested ("I'm interested") |
| `cost_max` | int >= 0 | – | `estimated_cost <= cost_max` **and** `currency = group.currency` (the raw number, whether per person or not) |
| `include_unpriced` | bool | `true` | with `cost_max`: also activities without a cost, or with another currency |
| `due_before` | `ApiDate` | – | `due_date <= due_before` (**inclusive**); activities without a due date are excluded |
| `q` | str 1..100 | – | case-insensitive substring of `title` (`LIKE` with `%` and `_` escaped) |
| `sort` | `ActivitySort` | `created_at` | `created_at`, `due_date`, `title`, `interest_count`, `estimated_cost` |
| `order` | `SortOrder` | `desc` | `asc` or `desc` |
| `cursor`, `limit` | | –, 50 | section 1.6 |

- `due_date` and `estimated_cost` sort with **nulls last** in both orders.
- Ties are broken by `id` descending, so paging is stable.
- `title` sorts with NOCASE.

### 8.8 events and calendar (tag `events`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /groups/{group_id}/calendar` | `get_group_calendar` | member | query `from`, `to`, `tz?`, `kinds*`, `category_id?` | 200 `CalendarResponse` (section 5.5) | 422 `range_too_large` |
| `POST /groups/{group_id}/events` | `create_event` | member | `EventWrite` | 201 `Event`; scheduling side effect (section 5.8) | 422 `invalid_rrule`, `invalid_reference` |
| `GET /events/{event_id}` | `get_event` | member | – | 200 `Event` (series definition plus `cancelled_occurrence_keys`) | – |
| `PUT /events/{event_id}` | `update_event` | creator, linked activity's owner, or admin+ | `EventUpdate` | 200 `Event` (edits the whole series; section 5.6 for exceptions) | 403; 409 `version_conflict`; 422 `invalid_rrule`, `invalid_reference` |
| `DELETE /events/{event_id}` | `delete_event` | same | – | 204 (the whole series) | 403 |
| `DELETE /events/{event_id}/occurrences/{occurrence_key}` | `cancel_occurrence` | same | – | 204 (idempotent) | 403; 404 (not an occurrence); 422 (malformed key, or a `one_time` event) |
| `POST /events/{event_id}/occurrences/{occurrence_key}/restore` | `restore_occurrence` | same | – | 204 (idempotent) | 403; 422 (malformed key) |

### 8.9 polls (tag `polls`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /activities/{activity_id}/polls` | `list_polls` | member | – | 200 `Poll[]` (oldest first) | – |
| `POST /activities/{activity_id}/polls` | `create_poll` | member | `PollCreate` | 201 `Poll` | 422 `limit_reached` (10 polls) |
| `GET /polls/{poll_id}` | `get_poll` | member | – | 200 `Poll` | – |
| `PUT /polls/{poll_id}` | `update_poll` | manager | `PollUpdate` | 200 `Poll` | 403 |
| `DELETE /polls/{poll_id}` | `delete_poll` | manager | – | 204 | 403 |
| `POST /polls/{poll_id}/close` | `close_poll` | manager | – | 200 `Poll`; sets `closed_at = now` (idempotent) | 403 |
| `POST /polls/{poll_id}/reopen` | `reopen_poll` | manager | – | 200 `Poll`; `closed_at = null`, and `closes_at = null` if it has passed | 403 |
| `POST /polls/{poll_id}/options` | `add_poll_option` | member | `PollOptionCreate` | 201 `Poll`; the option goes last | 409 `poll_closed`, `name_taken`; 422 `limit_reached` |
| `DELETE /polls/{poll_id}/options/{option_id}` | `delete_poll_option` | whoever added it (while it has no votes) or the manager | – | 200 `Poll`; the option's votes are removed | 403; 422 `limit_reached` (would leave fewer than 2) |
| `PUT /polls/{poll_id}/votes/me` | `set_my_vote` | member | `VoteRequest` | 200 `Poll`. **Replaces** the caller's whole vote set; empty = retract. Duplicate IDs are ignored. | 409 `poll_closed`; 422 `too_many_choices`, `invalid_reference` |

Rules for polls:
- A poll is **open** when `closed_at IS NULL AND (closes_at IS NULL OR closes_at > now)`. A
  `closes_at` in the past counts as closed.
- `closes_at` in a create or update must be in the future. An update may also resend the stored value
  unchanged.
- `allow_multiple` is fixed at creation. With `allow_multiple = false`, more than one ID gets
  `too_many_choices`.

### 8.10 wheel (tag `wheel`)

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /groups/{group_id}/wheel/candidates` | `list_wheel_candidates` | member | `WheelFilters` as query parameters (repeated `status`) | 200 `WheelCandidates` (section 10) | – |
| `POST /groups/{group_id}/wheel/spins` | `create_spin` | member | `SpinCreate` | 201 `WheelSpin` | 422 `not_enough_candidates`, `invalid_reference` |
| `GET /groups/{group_id}/wheel/spins` | `list_spins` | member | `cursor`, `limit` | 200 `WheelSpinPage` (newest first) | – |
| `POST /wheel/spins/{spin_id}/accept` | `accept_spin` | member | – | 200 `WheelSpin` (idempotent) | 409 `result_deleted` |

**Removed from the drafts:** `GET /groups/{id}/feed` (the `group_log` table stays), `weight_by_interest`,
the poll fields `is_anonymous`/`max_choices`/`allow_member_options`, and activity
`latitude`/`longitude`.

---

## 9. Response schemas (and request bodies)

Request bodies (`*Write`, `*Create`, `*Update`, `*Request`, `*Change`) apply the string rules in
section 1.4. Response models list every field.

```
# ---- enums ----
Role              = owner | admin | member
AssignableRole    = admin | member
ActivityStatus    = idea | planning | scheduled | done | dropped
ActivitySort      = created_at | due_date | title | interest_count | estimated_cost
SortOrder         = asc | desc
EventKind         = one_time | recurring | birthday
OccurrenceSource  = event | member_birthday
FieldType         = text | long_text | number | rating | url | select | year
InviteStatus      = valid | expired | revoked | exhausted
HealthStatus      = ok | degraded
DbStatus          = ok | error

# ---- common ----
Problem           { type: str, title: str, status: int, detail: str?, code: str, errors: FieldError[]?, request_id: str }
FieldError        { field: str, message: str, type: str }
Health            { status: HealthStatus, version: str, db: DbStatus }
UserPublic        { id: uuid, display_name: str, avatar_url: str? }      # deleted user: "Deleted user", null
Birthday          { month: int (1..12), day: int (1..31, valid for the month; Feb 29 allowed), year: int? (1900..current year; must form a real date) }
BirthdayPublic    { month: int, day: int }

# ---- auth ----
RegisterRequest   { email: str, password: str (10..128), display_name: str (1..50), timezone: str?,
                    device_label: str? (<=100), invite_code: str? }
LoginRequest      { email: str, password: str (1..128), device_label: str? (<=100) }
RefreshRequest    { refresh_token: str (1..128) }                    # also the body of /auth/logout
TokenPair         { access_token: str, refresh_token: str, token_type: str ("bearer"),
                    access_expires_in: int (seconds), refresh_expires_at: datetime }
AuthSession       { user: Me, tokens: TokenPair, joined_group: GroupSummary? }

# ---- me ----
Me                { id: uuid, email: str, display_name: str, avatar_url: str?, birthday: Birthday?,
                    timezone: str, locale: str?, created_at: datetime }
MeUpdate          { display_name: str (1..50), birthday: Birthday?, timezone: str, locale: str? (<=16),
                    avatar_url: str? }
PasswordChange    { current_password: str (1..128), new_password: str (10..128) }
AccountDeletion   { password: str (1..128) }

# ---- groups and members ----
GroupSummary      { id: uuid, name: str, emoji: str?, color: str?, member_count: int, my_role: Role,
                    created_at: datetime }
Group             { id, name, emoji?, color?, member_count, my_role, created_at,          # = GroupSummary fields
                    description: str?, currency: str, timezone: str, members_can_invite: bool,
                    created_by: UserPublic?, updated_at: datetime }
GroupCreate       { name: str (1..60), description: str? (<=500), emoji: str? (<=16), color: Color?,
                    currency: str = "EUR", timezone: str? (null -> caller's timezone),
                    members_can_invite: bool = true, seed_default_categories: bool = true }
GroupUpdate       { name: str (1..60), description: str?, emoji: str?, color: Color?, currency: str,
                    timezone: str, members_can_invite: bool }
TransferOwnership { user_id: uuid }
Member            { user: UserPublic, role: Role, joined_at: datetime,
                    birthday: BirthdayPublic?,   # null unless set and show_birthday is on (always shown on your own row)
                    show_birthday: bool? }       # your own row: your setting; other rows: null
RoleUpdate        { role: AssignableRole }
MemberSettingsUpdate { show_birthday: bool }

# ---- invites ----
Invite            { id: uuid, group_id: uuid, code: str, url: str, status: InviteStatus,
                    expires_at: datetime?, max_uses: int?, use_count: int, revoked_at: datetime?,
                    created_by: UserPublic?, created_at: datetime, can_delete: bool }
InviteCreate      { expires_in_hours: int = 168 (1..720), never_expires: bool = false (admin+ only;
                    expires_in_hours is then ignored), max_uses: int? (1..100; null = unlimited) }
InvitePreview     { code: str, status: InviteStatus, group: InviteGroupPreview,
                    invited_by_name: str? (the creator's display_name; no IDs on this public endpoint),
                    expires_at: datetime? }
InviteGroupPreview { name: str, emoji: str?, color: str?, member_count: int }

# ---- categories ----
FieldDef          { key: str, label: str, type: FieldType, options: str[]?, min: float?, max: float?,
                    show_on_card: bool = false }                               # section 6.1
Category          { id: uuid, group_id: uuid, parent_id: uuid?, name: str,
                    color: str?,                  # own color (null on a subcategory = inherit)
                    effective_color: str?,        # own ?? parent's
                    icon: str?, position: int,
                    field_defs: FieldDef[],             # own
                    effective_field_defs: FieldDef[],   # parent's + own (== field_defs for top-level)
                    created_by: UserPublic?, can_edit: bool, can_delete: bool,
                    created_at: datetime, updated_at: datetime }
CategoryNode      { ...all Category fields, subcategories: Category[] }
CategoryWrite     { name: str (1..40), parent_id: uuid?, color: Color? (required when parent_id is null),
                    icon: str? (<=40),
                    position: int? (0..1000000; null: append on create / keep on update),
                    field_defs: FieldDef[] = [] (<=12) }

# ---- activities ----
Link              { url: str, label: str? (<=60) }
CardAttribute     { key: str, label: str, type: FieldType, value: any (string | number) }
OccurrenceRef     { event_id: uuid, occurrence_key: str, all_day: bool, starts_at: datetime?, start_date: date? }
ActivitySummary   { id: uuid, group_id: uuid, title: str, status: ActivityStatus, category_id: uuid?,
                    owner: UserPublic?, due_date: date?, estimated_cost: int?, currency: str?,
                    cost_per_person: bool,
                    interest_count: int, i_am_interested: bool,
                    poll_count: int, open_poll_count: int, my_unvoted_poll_count: int,  # "Vote" badge
                    card_attributes: CardAttribute[],
                    next_occurrence: OccurrenceRef?,
                    can_edit: bool, can_delete: bool,
                    created_at: datetime, updated_at: datetime }
Activity          { ...all ActivitySummary fields,
                    description: str?, notes: str?, location_name: str?, address: str?,
                    links: Link[], attributes: object (key -> string | number; section 6.4),
                    interested_users: UserPublic[], created_by: UserPublic?,
                    status_changed_at: datetime, completed_at: datetime?, version: int,
                    events: EventRef[] }                    # linked events, by window_start
EventRef          { id: uuid, kind: EventKind, title: str, all_day: bool, starts_at: datetime?,
                    start_date: date?, rrule: str? }
ActivityWrite     { title: str (1..120), description: str? (<=5000), notes: str? (<=5000),
                    category_id: uuid?, owner_id: uuid?, due_date: date?,
                    estimated_cost: int? (0..10000000),
                    currency: str? (with a cost: null -> group currency; ignored and stored null without a cost),
                    cost_per_person: bool = true, location_name: str? (<=120), address: str? (<=300),
                    links: Link[] = [] (<=10), attributes: object = {} }
ActivityCreate    { ...ActivityWrite, status: ActivityStatus = idea }
ActivityUpdate    { ...ActivityWrite, version: int }
StatusChange      { status: ActivityStatus }
InterestState     { activity_id: uuid, interested: bool, interest_count: int, interested_users: UserPublic[] }
ActivityPage      { items: ActivitySummary[], next_cursor: str? }

# ---- events and calendar ----
EventWrite        { kind: EventKind, title: str (1..120), description: str? (<=5000), all_day: bool,
                    starts_at: datetime?, ends_at: datetime?, start_date: date?, end_date: date?,
                    timezone: str? (null -> group timezone), rrule: str? (<=200),
                    category_id: uuid?, activity_id: uuid?, location_name: str? (<=120),
                    address: str? (<=300) }                                    # rules: section 5.8
EventUpdate       { ...EventWrite, version: int }
Event             { id: uuid, group_id: uuid, kind: EventKind, title: str, description: str?,
                    all_day: bool, starts_at: datetime?, ends_at: datetime?, start_date: date?,
                    end_date: date?, timezone: str, rrule: str? (canonical), category_id: uuid?,
                    color: str? (effective category color), activity_id: uuid?,
                    location_name: str?, address: str?, cancelled_occurrence_keys: str[],
                    version: int, created_by: UserPublic?, can_edit: bool, can_delete: bool,
                    created_at: datetime, updated_at: datetime }
Occurrence        { occurrence_key: str, source: OccurrenceSource, event_id: uuid?, user_id: uuid?,
                    group_id: uuid? (null only for de-duplicated birthdays in /me/calendar),
                    kind: EventKind, title: str, all_day: bool,
                    starts_at: datetime?, ends_at: datetime?,      # timed
                    start_date: date?, end_date: date?,            # all-day (end inclusive)
                    timezone: str?, category_id: uuid?, color: str?, activity_id: uuid?,
                    is_recurring: bool, can_edit: bool }
CalendarResponse  { from_date: date, to_date: date (exclusive), tz: str (the zone used),
                    occurrences: Occurrence[] }                               # sorted, section 5.5

# ---- polls ----
PollOption        { id: uuid, label: str, url: str?, position: int, vote_count: int,
                    voters: UserPublic[], added_by: UserPublic?, can_delete: bool }
Poll              { id: uuid, group_id: uuid, activity_id: uuid, question: str, allow_multiple: bool,
                    closes_at: datetime?, closed_at: datetime?, is_open: bool, options: PollOption[],
                    my_option_ids: uuid[], total_voters: int (distinct voters),
                    winning_option_ids: uuid[] (max vote_count > 0; ties give several; empty with no votes),
                    created_by: UserPublic?, can_manage: bool, created_at: datetime, updated_at: datetime }
PollOptionCreate  { label: str (1..100), url: str? }
PollCreate        { question: str (1..200), allow_multiple: bool = false, closes_at: datetime? (future),
                    options: PollOptionCreate[] (2..20; labels unique case-insensitively, else
                    422 validation_error) }
PollUpdate        { question: str (1..200), closes_at: datetime? }
VoteRequest       { option_ids: uuid[] (0..20) }

# ---- wheel ----
WheelFilters      { status: ActivityStatus[] = [idea, planning] (1..5 items), category_id: uuid?,
                    include_subcategories: bool = true, interested_by: uuid?, owner_id: uuid?,
                    cost_max: int? (>=0), include_unpriced: bool = true, due_before: date? }
WheelCandidates   { items: ActivitySummary[] (<=50), total: int }
SpinCreate        { filters: WheelFilters, activity_ids: uuid[]? (<=50 items; duplicates ignored;
                    fewer than 2 distinct -> 422 not_enough_candidates; section 10) }
WheelCandidate    { id: uuid, title: str, category_id: uuid?, color: str? }
WheelSpin         { id: uuid, group_id: uuid, spun_by: UserPublic?, filters: WheelFilters,
                    candidates: WheelCandidate[], result_index: int,
                    result: WheelCandidate (= candidates[result_index]),
                    result_activity_id: uuid? (null once the activity is deleted),
                    accepted_at: datetime?, accepted_by: UserPublic?, created_at: datetime }
WheelSpinPage     { items: WheelSpin[], next_cursor: str? }
```

Derived counters in `ActivitySummary`:
- `poll_count`: all polls of the activity.
- `open_poll_count`: open polls (section 8.9).
- `my_unvoted_poll_count`: open polls where the caller has no vote. The card shows a **"Vote"
  badge** while it is above 0. The polls themselves appear in the activity detail.

---

## 10. Wheel semantics

The **server picks** the result. Everyone sees the same result, nobody can quietly re-roll on their
own phone, and the history feeds the recap ("the wheel decided 14 times").

1. **Candidate pool.** Activities of the group that match `WheelFilters`, using the same semantics as
   `list_activities`. `status` defaults to `idea`, `planning`.
   - **The client defaults its "Only ideas I'm interested in" toggle to ON**, which sends
     `interested_by=<my id>`. The server has no default for `interested_by`.
2. **`GET …/wheel/candidates`** returns `total` (the pool size) and `items`: the first **50** by
   `created_at desc, id desc`.
3. **`POST …/wheel/spins` without `activity_ids`:**
   - fewer than 2 in the pool → 422 `not_enough_candidates`;
   - more than 50 → a uniform random sample of 50 (`rng.sample`);
   - the slice order is `created_at desc, id desc`.
4. **With `activity_ids`** (the user's hand-picked subset of 2..50 activities):
   - more than 50 items → 422 `validation_error`; duplicate IDs are ignored (the first one keeps
     its position);
   - each must be an existing activity of this group, else 422 `invalid_reference`;
   - fewer than 2 distinct IDs → 422 `not_enough_candidates`;
   - the filters are **not** applied again; they are stored for display only;
   - the slice order is the order of `activity_ids`.
5. **Pick:** `result_index = rng.randrange(len(candidates))`.
   - `rng` is `secrets.SystemRandom()` in production and injectable (a seeded `random.Random`) in
     tests.
   - **Every slice has the same weight.** There is no interest weighting, because unequal odds on
     equal slices would misrepresent them.
6. **Snapshot:** `candidates = [{id, title, category_id, color}]`, where `color` is the effective
   category color at spin time.
   - `result_activity_id = candidates[result_index].id`; log `wheel.spun`.
   - The snapshot means history survives later edits and deletions.
7. **Client:**
   - replace the wheel's slices with `spin.candidates` in the server's order, then animate to
     `result_index` (`wheel_math.dart` always lands on it);
   - with `MediaQuery.disableAnimations`, show the result immediately;
   - disable Spin below 2 candidates.
8. **Accept** (`POST /wheel/spins/{id}/accept`, any member):
   - if `accepted_at` is already set, return the spin unchanged (idempotent);
   - if `result_activity_id` is null (the activity was deleted) → 409 `result_deleted`;
   - otherwise set `accepted_at` and `accepted_by`; if the activity's status is `idea`, it becomes
     **`planning`** (logged `via: "wheel"`); other statuses stay; log `wheel.accepted`.
   - The client then offers **"Schedule it"**, which opens the event form with `activityId`.
9. **History:** `list_spins`, newest first, cursor-paginated.

---

## 11. Future-proofing (not in the MVP, not blocked)

**Push notifications**
- Tables:
  - `device_tokens(id, user_id, platform ios|android|web, token unique, app_version, last_seen_at)`;
  - `notification_prefs(group_id, user_id, …)`;
  - a transactional outbox, `notification_outbox(id, user_id, group_id, type, payload json,
    dedupe_key unique, scheduled_for, sent_at, attempts, last_error)`. Its rows are derived from
    `group_log` writes in the same transaction.
- Event reminders come from a scheduler: in-process, or the same image as a second compose service.
  It calls `recurrence.expand` every minute and inserts outbox rows with the dedupe key
  `event:{id}:{occurrence_key}:{offset}`. A sender delivers them through FCM HTTP v1.
- What the MVP already gets right for this: every mutation goes through the service layer (one hook
  point), `group_log` exists, recurrence is a pure function, and `users.timezone` exists.

**Availability heatmap** (built: section 13)
- Table `availability(user_id, date, slot all_day|morning|afternoon|evening, status free|maybe|busy,
  updated_at)` with `UNIQUE(user_id, date, slot)`. It is per user, so it shows in every group the user
  belongs to.
- `GET /groups/{id}/availability?from&to` would return counts per date and slot, plus the best days
  ranked.
- It needs nothing new from the MVP beyond floating dates and `groups.timezone`.

**Monthly and annual recap** (built: section 14)
- It relies on data that can't be rebuilt later, so the MVP stores it from day one:
  - `created_by_id` everywhere;
  - `activities.completed_at` and `status_changed_at`;
  - `group_log` (status transitions and their actors);
  - `wheel_spins.accepted_at`;
  - `created_at` on votes and interests;
  - `memberships.joined_at`;
  - `groups.timezone` for period boundaries.
- Stats:
  - "Most active planner": `group_log` counts per actor of `activity.created`, `event.created`,
    `poll.created`, and `activity.status_changed` to `done`.
  - "Memories made": activities with `completed_at` in the period.
  - "Top category": the most common top-level category among done activities.
- Computed with SQL on request, and cached in `recaps(group_id, period, period_start, payload json)`
  if needed.

**Smaller items**
- An HttpOnly-cookie auth mode for web, now possible because of same-origin hosting.
- iOS Universal Links (`apple-app-site-association`, served like `assetlinks.json`) and TestFlight,
  once a Mac and an Apple account exist.
- TMDB/OMDb auto-fill of `attributes` (needs an API key).
- Backlog and wheel filters on attributes (`json_extract`, or generated columns).
- A group feed UI (`GET /groups/{id}/feed` over `group_log`).
- A personal calendar UI over `/me/calendar`.
- Single-occurrence edits through `override_*` columns on `event_exceptions`.
- Email verification and password reset, once SMTP exists.
- A Postgres move. UUIDs, UTC instants and plain SQL keep it cheap; `COLLATE NOCASE` becomes `citext`
  or `lower()` indexes.

---

## 12. Client codegen notes

**Backend settings**
```python
FastAPI(title="Friends API", version="1",
        openapi_url="/api/v1/openapi.json" if settings.docs_enabled else None,
        docs_url="/api/v1/docs" if settings.docs_enabled else None, redoc_url=None,
        generate_unique_id_function=lambda route: route.name,   # operationId = handler name
        separate_input_output_schemas=False)                    # no Foo-Input / Foo-Output pairs
```
- **operationIds** are the handler names listed in section 8 and are globally unique. A test turns
  FastAPI's "Duplicate Operation ID" warning into a failure.
- **Tags:** each router has exactly one tag, which gives one generated client per tag. The tags are
  `health`, `auth`, `users`, `groups`, `invites`, `categories`, `activities`, `events`, `polls` and
  `wheel`, producing `HealthClient`, `AuthClient`, … `WheelClient` under the root `FriendsApi`.
- Enums are named `StrEnum`s. Page types are concrete subclasses.
- **Error responses:** every router declares its error responses with the `Problem` model under
  `application/problem+json`, including 422. FastAPI's default `HTTPValidationError`/`ValidationError`
  schemas **must not appear** in `openapi.json`.
- `attributes` and `CardAttribute.value` are free-form (`dict[str, Any]` / `Any`), so Dart sees
  `Map<String, dynamic>` / `dynamic`. Values are validated by the server.
- **The snapshot:** `uv run python -m friends_api.cli export-openapi` writes `backend/openapi.json`
  (indent 2, LF). Backend CI runs it and then `git diff --exit-code backend/openapi.json`.

**Generator (`app/swagger_parser.yaml`)**
```yaml
swagger_parser:
  schema_path: ../backend/openapi.json
  output_directory: lib/core/api/generated
  json_serializer: freezed
  use_freezed3: true
  root_client: true
  root_client_name: FriendsApi
  put_clients_in_folder: true
  enums_to_json: true
  unknown_enum_value: true      # new server enum values don't crash old app builds
  # PUT bodies send explicit nulls (section 1.4). In swagger_parser 1.44 `true` annotates optional
  # nullable fields with includeIfNull: false, which drops them; `false` keeps json_serializable's
  # default (include nulls). See ADR 0003.
  include_if_null: false
  mark_files_as_generated: true
```
- `dart run swagger_parser` output is **committed** (and marked `linguist-generated`).
- `*.g.dart` and `*.freezed.dart` are **not** committed; CI builds them with
  `dart run build_runner build -d`.
- The generated DTOs **are** the app's models. There is no mapping layer.

**Wire rules the client must follow.** The M4 spike tests check each of these against a fake adapter:
1. **Repeated query parameters:** configure Dio with `listFormat: ListFormat.multi`, so a list goes out
   as `status=idea&status=planning`.
2. **Enum query values** go out as their wire values (`kinds=one_time`, not `oneTime`).
3. **Dates:** build them with the `DateOnly` helpers as a **UTC midnight** (`DateTime.utc(y, m, d)`),
   which goes out as `2026-10-01T00:00:00.000Z`. Not a local `DateTime(y, m, d)`: where DST starts at
   midnight (e.g. `America/Santiago` on 2026-09-06) local midnight doesn't exist and that value is
   01:00. The server's `ApiDate` accepts `YYYY-MM-DD` and midnight date-times with a `T` or space
   separator, with or without `Z`, and rejects any other time. Dates in responses parse to local
   `DateTime`s, so the client passes them through `DateOnly.from` before sending them back.
   swagger_parser `field_parsers` are not usable with freezed, so there is no per-field converter.
4. **Instants:** every instant `DateTime` put into a generated model or query goes through `.toUtc()`
   first. One helper does it (`ApiInstant.of`), and one test enforces it. A local `toIso8601String()`
   has no offset and gets a 422.
5. **Explicit nulls** in PUT bodies (`include_if_null: false`, see above and ADR 0003).
6. **Problem decoding:** a Dio interceptor turns `application/problem+json` into a
   `ProblemException(status, code, detail, errors)`, and the UI maps `errors[].field` onto form fields.

**Auth behaviour in the client**
- The access token lives only in memory. The refresh token goes in `flutter_secure_storage`. On web
  that only obfuscates it, which is accepted for the MVP given same-origin hosting and 15-minute access
  tokens.
- The auth interceptor is a `QueuedInterceptorsWrapper` with a single-flight refresher that uses a bare
  Dio.
  - It refreshes when the token expires within 30 s, and once on **401 `token_expired`**, then retries
    once.
  - Any other 401 (`unauthenticated`, `refresh_invalid`, `refresh_reuse_detected`) signs the user out.
  - A network error never signs the user out.
  - Public calls skip the interceptor: health, login, register, refresh, logout, and the invite
    preview.
- Invite codes are normalized on the client exactly as in section 4.7. The "join with code" dialog also
  accepts a pasted `…/join/<code>` URL.
- On 409 `version_conflict`: show "Reload" only.
- Occurrence times are shown in device-local time with **no timezone label**.
- The client doesn't expand recurrence. It builds and validates rules with `rrule_spec.dart`
  (section 5.2), and the server returns occurrences.
- The environment's `API_BASE_URL` is the origin only (the generated paths include `/api/v1`). An empty
  value means `Uri.base.origin`, for the same-origin web build.

**Versioning**
- The API stays `v1`. Changes are additive: new fields, and new enum values that old clients tolerate.
- A breaking change would add `/api/v2`, served next to v1.
- Release tags are `backend-vX.Y.Z` and `app-vX.Y.Z`. The schema version string stays `"1"`.

---

## 13. Availability (post-MVP, issue #16)

Members say when they are free; each group gets a heatmap and its best days. Decisions:
[ADR 0004](../adr/0004-availability.md).

**Storage.** `availability(id, user_id -> users CASCADE, date, slot, status, created_at, updated_at)`,
`UNIQUE (user_id, date, slot)`.
- `slot`: `all_day | morning | afternoon | evening`.
- `status`: `free | maybe | busy`.
- It is **per user**, not per group: one answer shows in every group the user belongs to. Nothing
  is deleted when a membership ends, because nothing belongs to the group.

**Endpoints**

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /me/availability` | `get_my_availability` (tag `users`) | user | query `from`, `to` (`ApiDate`, `to` exclusive) | 200 `MyAvailability`: my entries by date, then slot | 422 `range_too_large` |
| `PUT /me/availability` | `update_my_availability` (tag `users`) | user | `MyAvailabilityUpdate` | 200 `MyAvailability`. **Replaces** my entries with `from_date <= date < to_date`; a slot left out becomes unknown. | 422 `range_too_large`, `validation_error` (an entry outside the range: `entries.<i>.date`; a repeated date and slot: `entries.<i>`) |
| `GET /groups/{group_id}/availability` | `get_group_availability` (tag `availability`) | member | query `from`, `to` | 200 `GroupAvailability` | 422 `range_too_large` |

Ranges: `to <= from` → 422 `validation_error`; more than **92 days** → 422 `range_too_large`.

**Resolving an answer** (only the group's *current* members count):
- A part of the day (`morning`, `afternoon`, `evening`) is its own entry, else the date's `all_day`
  entry, else unknown.
- The whole day is the `all_day` entry. Without one, it comes from the three parts:
  - free when all three are free;
  - maybe when any is free or maybe;
  - busy when all three are busy;
  - unknown otherwise.

**Score and best days**
- A day's score is `free + 0.5 × maybe`, over the whole-day statuses.
- `best_days` lists up to 10 days with a score above 0. The highest score comes first; ties go to
  fewer busy, then the earlier date.

**Privacy**
- Counts are shown for every slot. Who is **free** or **maybe** is listed by name.
- **Busy stays a count only**: nobody sees who said no.

```
AvailabilitySlot   = all_day | morning | afternoon | evening
AvailabilityStatus = free | maybe | busy
AvailabilityEntry      { date: date, slot: AvailabilitySlot, status: AvailabilityStatus }
AvailabilityEntryWrite { date: date, slot: AvailabilitySlot, status: AvailabilityStatus }
MyAvailability         { from_date: date, to_date: date (exclusive), entries: AvailabilityEntry[] }
MyAvailabilityUpdate   { from_date: date, to_date: date (exclusive, <= 92 days),
                         entries: AvailabilityEntryWrite[] = [] }
SlotCounts        { slot, free: int, maybe: int, busy: int, unknown: int,
                    free_users: UserPublic[], maybe_users: UserPublic[] }
DayAvailability   { date: date, score: float, slots: SlotCounts[] (all_day, morning, afternoon, evening) }
BestDay           { date: date, score: float, free: int, maybe: int, busy: int, unknown: int }
GroupAvailability { from_date: date, to_date: date (exclusive), member_count: int,
                    days: DayAvailability[] (every date of the range), best_days: BestDay[] (<= 10) }
```

## 14. Recap (post-MVP, issue #17)

A group's "Wrapped": highlight stats for a calendar month or year. Decisions:
[ADR 0005](../adr/0005-recap.md).

| Endpoint | operationId | Auth | Request | Success | Extra errors |
|---|---|---|---|---|---|
| `GET /groups/{group_id}/recap` | `get_group_recap` (tag `recap`) | member | query `period` (`month \| year`, required), `start` (`ApiDate`, optional) | 200 `Recap` | 422 `validation_error` on `query.start` |

**Periods**
- A period is a calendar month or year **in the group's timezone**: `[start, end)` local midnights,
  compared as UTC instants. A month that contains a DST change still has its local days.
- `start` must be the period's first day (the 1st, or 1 January). Omitted, it is the current period.
- Only past and current periods have a recap. Errors on `query.start` (422 `validation_error`):
  - "Must be the first day of a month." (or "…of a year.");
  - "Recaps start in 2000.";
  - "This period hasn't started yet."
- `complete` is false while the period is still running. Its numbers can still change.

**Stats**, all over the group's rows in the period:
- **Memories** (`memory_count`, `memories`): activities that are `done` with `completed_at` in the
  period, in completion order. At most 100 are listed; all are counted.
- **Planners** (`planners`): `group_log` rows per actor:
  - `ideas` counts `activity.created`;
  - `events` counts `event.created`;
  - `polls` counts `poll.created`;
  - `done` counts `activity.status_changed` to `done`.

  `score` is their sum. The top 3 are listed by score, then name. They include former members.
  Rows without an actor (a deleted account) count in the totals only.
- **Top categories** (`top_categories`): up to 3 top-level categories by memories. Subcategories
  count under their parent; uncategorized memories don't count.
- **Totals**: the log rows `activity.created` (`ideas_added`), `event.created` (`events_planned`),
  `poll.created` (`polls_created`) and `member.joined` (`new_members`), and the spins accepted
  (`wheel_decisions`).
- **Extras**:
  - `top_poll`: the poll created in the period with the most distinct voters (ties go to the
    earlier poll). Null without votes.
  - `longest_wait`: the memory with the longest time from `created_at` to `completed_at`, in whole
    days (ties go to the earlier completion).
  - `busiest_month`: for a year, the month with the most memories (ties go to the earlier month).
    Null for a month.
  - `most_wanted`: the idea with the most interest added before the period's end, among
    activities that are **still** `idea` or `planning` today and were created before the end.

The recap is computed on request, from the rows as they are now. A deleted activity leaves its
period's memories. There is no cache table, because GET handlers never write (section 1.7).

```
RecapPeriod   = month | year
RecapActivity { id: uuid, title: str, category_id: uuid | null, color: str | null (effective),
                created_at: ts, completed_at: ts }
RecapPlanner  { user: UserPublic, score: int, ideas: int, events: int, polls: int, done: int }
RecapCategory { id: uuid, name: str, color: str | null, icon: str | null, count: int }
RecapPoll     { id: uuid, question: str, activity_id: uuid, activity_title: str, voters: int }
RecapWait     { activity: RecapActivity, days: int }
RecapMonth    { month: date (first day), count: int }
RecapIdea     { activity_id: uuid, title: str, color: str | null, interested: int }
Recap { period: RecapPeriod, start: date, end: date (exclusive), timezone: str, complete: bool,
        memory_count: int, memories: RecapActivity[] (<= 100), planners: RecapPlanner[] (<= 3),
        top_categories: RecapCategory[] (<= 3), ideas_added: int, events_planned: int,
        polls_created: int, wheel_decisions: int, new_members: int,
        top_poll: RecapPoll | null, longest_wait: RecapWait | null,
        busiest_month: RecapMonth | null, most_wanted: RecapIdea | null }
```
