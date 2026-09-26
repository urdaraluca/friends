# ADR 0002: Domain and API conventions

- **Status:** Accepted
- **Date:** 2026-09-25
- **Related:** [ADR 0001](0001-stack-and-monorepo.md). The full rules are in the
  [API contract](../api/contract.md); this ADR records the choices and why they were made.

## Context

The API is consumed by a generated Dart client (swagger_parser: retrofit + freezed). It runs on
SQLite on a Pi, and later features must be able to build on it without needing history that was
never recorded: push notifications, an availability heatmap, and a Spotify-Wrapped-style recap. The conventions
therefore have to suit code generation, a single SQLite writer, and future analytics.

## Decision

| Convention | Decision | Why |
|---|---|---|
| IDs | **UUIDv7** everywhere (stdlib `uuid.uuid7()`) | Can't be guessed in shared links, sorts by time (good for indexes and cursors), survives a move to Postgres. |
| Instants | **UTC**, ISO 8601 with `Z`; a `UTCDateTime` TypeDecorator rejects naive values; requests use `AwareDatetime`; the client sends `.toUtc()` | One timeline for the server, the recap and notifications; there are no naive-datetime bugs. |
| Dates | `YYYY-MM-DD` through an **`ApiDate`** validator. It also accepts a midnight date-time, rejects any other time, and never converts between zones. | swagger_parser/freezed can't mark fields as date-only, so this accepts what Dart actually sends without shifting days. |
| Timezones | IANA names (`tzdata` package). Invalid at register → `UTC`; invalid calendar `tz` → the user's zone; elsewhere 422 | Devices sometimes report odd zone names; explicit pickers are strict. |
| JSON | snake_case under `/api/v1`, no aliases; every field is present in responses (null, never omitted); array query parameters are repeated keys | Matches Pydantic with no configuration; codegen stays predictable. |
| Errors | **RFC 9457 problem+json** with a stable `code` and `errors[]` for field-level 422s; `input`/`ctx` stripped | One error shape for every client; the UI branches on codes, not text; no password echo. |
| Membership privacy | **Non-members get 404** for any group resource, identical to a missing one. Loader dependencies return `(entity, membership)`. | Doesn't reveal that a group exists. A test walks every route with a UUID path parameter. |
| Updates | **Full-object PUT** with a **`version`** field (409 `version_conflict`) on activities and events; small command endpoints for status, interest, votes, close/reopen, spin accept; the client offers only "Reload" on a conflict | A generated Dart model can't tell "unset" from `null`, so PATCH can't clear a field. Commands keep quick taps from conflicting with edits. |
| Pagination | Cursor-based, `{items, next_cursor}`, with an opaque cursor (an offset in the MVP) | Can become keyset-based without a client change. |
| Codegen | operationId = handler name, one tag per router, named `StrEnum`s, concrete page classes, committed `backend/openapi.json` | Clean Dart names; API diffs are reviewable. |
| Sign-up | **Invite-only by default** (`REGISTRATION_MODE=invite_only`): registration needs a valid group invite code and joins that group; the first user comes from `cli create-user`; password reset is a CLI command | A private app for friend groups; no SMTP in the MVP. |
| Invites | 10-character Crockford base32 codes, normalized on the server and client; uses counted with a conditional UPDATE | Easy to type and share; no race on `max_uses`. |
| Deletion | Hard delete with FK cascades for domain rows; `dropped` status as the archive; **accounts are anonymized** (email freed, ownership transferred first) | Authored history stays meaningful ("Deleted user"); required for app-store account deletion. |
| Enums | Stored as VARCHAR with no DB CHECK; clients accept unknown values | Adding a value needs no SQLite table rebuild and doesn't crash old app builds. |
| Case-insensitive names | `COLLATE NOCASE` columns with plain partial unique indexes | `alembic check` can see them, unlike `lower()` expression indexes. |
| Custom fields | `categories.field_defs` JSON (at most 12, typed: text, long_text, number, rating, url, select, year); `activities.attributes` JSON; **validated in the service layer** against the category's effective definitions (a subcategory inherits the parent's); stale values are ignored on read and dropped on the next write; no type changes | "Movie night" gets genre, IMDb rating, link and year without a schema migration per category; JSON avoids an EAV table at this scale. |
| Recurrence | A restricted RRULE subset, stored in canonical form and expanded by the server per range query in the event's timezone. Profile birthdays are virtual occurrences, and 29 February falls on 28 February in non-leap years. Shared fixtures are in `docs/api/rrule_cases.json`. | Correct across DST changes; nothing silently skips short months; the client and server can't drift. |
| Wheel | The server picks with `secrets.SystemRandom` and stores a snapshot of the candidates | Everyone sees the same result; the history survives deletes and feeds the recap. |
| History | An append-only **`group_log`**, written in the same transaction as each change; `created_by_id` on every authored row, plus `status_changed_at` and `completed_at` on activities | The recap and notifications need history that can't be rebuilt later. No feed UI in the MVP. |
| Reads | GET handlers never write; write requests use `BEGIN IMMEDIATE` | Predictable SQLite locking with a single writer. |

## Consequences

- Clients send complete PUT bodies with explicit nulls (the generator setting is in ADR 0003).
  Request fields never give "omitted" and "null" different meanings (for example
  `InviteCreate.never_expires` instead of a null expiry).
- Every new group-scoped mutation must write a `group_log` row and respect the loader and policy functions. The
  `can_*` flags in responses come from those same policy functions.
- Attribute queries (filters on genre or rating) aren't indexed. That is acceptable at this scale;
  `json_extract` or generated columns can come later.
- Changing a convention means updating the contract, the OpenAPI snapshot and the generated client in
  the same PR.
- [ADR 0003](0003-client-codegen.md) (client codegen) records the results of the M4 spike: the date
  and enum wire formats, repeated query parameters, problem decoding, and explicit nulls.
