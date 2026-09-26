# ADR 0003: Client codegen and wire rules

- **Status:** Accepted
- **Date:** 2026-09-26
- **Related:** [ADR 0001](0001-stack-and-monorepo.md), [ADR 0002](0002-domain-and-api-conventions.md),
  [API contract](../api/contract.md) sections 1.3–1.5 and 12. Spike tests:
  `app/test/core/api/wire_rules_test.dart` (fixture in `app/test/core/api/spike/`).

## Context

The Flutter app talks to one API that we also own. Hand-written DTOs and endpoint calls would drift
from the backend, and every later milestone (groups, backlog, wheel, polls, calendar) adds endpoints.
The backend already publishes a clean OpenAPI document (`backend/openapi.json`: operationId = handler
name, one tag per router, named enums, `Problem` for every error). We needed to know whether the
generated client puts exactly what the contract expects on the wire (repeated query keys, enum wire
names, dates, UTC instants, explicit nulls in PUT bodies, problem+json) before building screens on it.

## Decision

1. **swagger_parser + retrofit + freezed.** `dart run swagger_parser` reads `backend/openapi.json`
   (settings in `app/swagger_parser.yaml`) and writes one retrofit client per tag (`AuthClient`,
   `UsersClient`, …) under a root `FriendsApi`, plus freezed/json_serializable models.
   - The **generated DTOs are the app's models.** There is no mapping layer.
   - `enums_to_json: true` and `unknown_enum_value: true`: every enum gets `toJson()`, a `toString()`
     that returns the wire value, and a `$unknown` fallback, so a new server value doesn't crash an
     old app build.
2. **The client is committed.** `lib/core/api/generated/` is swagger_parser output, marked
   `linguist-generated`, never hand-edited and never run through `dart format` (a regenerate must
   give no diff). Only the build_runner outputs (`*.g.dart`, `*.freezed.dart`) are gitignored and
   rebuilt locally and in CI with `dart run build_runner build -d`.
3. **`include_if_null: false`**, not `true` as the draft contract said. In swagger_parser 1.44,
   `true` annotates optional nullable fields with `@JsonKey(includeIfNull: false)`, which **drops**
   the nulls; `false` emits no annotation, so json_serializable's default (include nulls) applies and
   PUT bodies carry every field. The contract (sections 1.4 and 12) now says so.
4. **A thin hand-written layer around it** (`lib/core/`), which later screens reuse:
   - `network/dio_provider.dart`: the main Dio (account stamp + auth + problem interceptors) and a
     bare Dio (public calls, refresh, retries). `baseUrl` is the origin only,
     `listFormat: ListFormat.multi`, connect timeout 10 s, receive timeout 20 s.
   - `api/api_providers.dart`: `friendsApiProvider` and one provider per generated client, plus
     `publicApiProvider` on the bare Dio for the public endpoints (health, login, register, refresh,
     logout, invite preview), so they never queue behind a token refresh.
   - `api/api_exception.dart`: every failure is a sealed `ApiException`: `ProblemException`
     (status, code, detail, errors, requestId, retryAfter), `NetworkException` or
     `UnexpectedApiException`. `apiCall(...)` unwraps Dio's wrapper.
   - `api/date_only.dart` (`DateOnly`) and `api/api_instant.dart` (`ApiInstant.of`) for the two
     kinds of `DateTime` (see the wire rules below).
   - `forms/field_errors.dart`: maps `errors[].field` onto form fields; `api/api_error_messages.dart`
     turns any `ApiException` into a friendly sentence.
5. **Auth behaviour** (contract sections 4 and 12): the access token lives in memory
   (`TokenHolder`), the refresh token in `flutter_secure_storage` (`TokenStore`). `TokenRefresher`
   is single-flight, re-reads the stored refresh token right before `POST /auth/refresh`, and uses
   the bare Dio. `AuthInterceptor` is a `QueuedInterceptorsWrapper`: it skips public calls, refreshes
   proactively when the token expires within 30 s, and on `401 token_expired` refreshes once (or
   just retries if another request already did) and retries once. Any other problem+json 401 signs
   out; a 401 that isn't problem+json (a proxy, a captive portal) and a network error never do.
   Session expiry reaches `AuthController` through a callback, so there is no provider cycle.
   Logout is local-first: the tokens are cleared at once, then `POST /auth/logout` is sent.

   **Web tabs** share the stored refresh token (local storage) but each has its own access token
   and `AuthController`. Two consequences:
   - A session that ends by itself (a 401) deletes the stored refresh token only if it is still the
     one this tab last read or saved (`TokenRefresher.clear(onlyIfOwn: true)`), so a newer session
     stored by another tab (after a password change, or a new sign-in) survives. Explicit logout,
     logout-all and account deletion still clear it.
   - A refresh can pick up another account's session (another tab signed in as someone else).
     `AccountStampInterceptor` stamps every request with the signed-in user's ID when it is issued,
     and `AuthInterceptor` never sends or retries it with a token whose `sub` is another user: the
     request fails, and `AuthController.accountChanged` goes back to `AuthUnknown` and restores, so
     `currentUserId` changes and every cache resets.

   The unit tests drive this through a fake adapter. A one-off run of the same stack against the
   real backend (`ACCESS_TOKEN_TTL_MINUTES=1`, M4) behaved the same way. After 33 s, one request
   caused exactly one proactive refresh. After the token had expired (past the server's 30 s leeway),
   5 concurrent `GET /me` calls got `401 token_expired`, which led to exactly one refresh and 5
   successful retries. A new container restored the session from the stored refresh token. A
   relaunch with the server unreachable stayed `AuthUnknown` with a `NetworkException` and kept the
   stored token. After logout, that token got `401 refresh_invalid`.

   That run exercised the Dart stack only, not a browser. It does **not** replace the manual
   acceptance check of issue #3, which is still open: steps 1–5 in Chrome (DevTools network log,
   `flutter_secure_storage` on web, path URLs, a page reload on `/register?invite=…` and on
   `/profile`) and on the Android emulator.

## Wire rules and what the spike showed

The M4 API has no list or enum query parameters and no date fields, so the spike runs the **same
generator settings** on a tiny FastAPI app (`app/test/core/api/spike/spike_api.py`, built with the
backend's `RequestModel` and `install_openapi`) and drives the generated client through the app's
real Dio and interceptors against a fake `HttpClientAdapter`. Rule 5 is also checked on the real
`MeUpdate`.

| # | Rule | Result |
|---|---|---|
| 1 | Array query parameters are repeated keys | Confirmed. With `ListFormat.multi`, `status: [idea, planning]` goes out as `status=idea&status=planning`, never `status[]=`. |
| 2 | Enum query values use wire names | Confirmed, on two different code paths. **Lists:** retrofit passes the list to Dio, which calls `toString()`; the generated enums return their wire value, so `kinds=one_time&kinds=birthday`. **Single values:** retrofit calls `toJson()`, so `sort: ActivitySort.dueDate` sends `sort=due_date`. Never send `$unknown`: as a single value its `toJson()` throws a `StateError` before the request goes out; in a list its `toString()` isn't a wire value. Query parameters with a schema default get that default in the generated signature, so the client always sends them (`sort=created_at&include_subcategories=true`). Query booleans go out as `true`/`false` (contract section 1.4). |
| 3 | Dates are UTC midnights (`DateOnly`) | Confirmed, after one correction. A date goes out through `toIso8601String()`, in queries (retrofit calls it) and bodies (json_serializable does). The draft rule, a naive local `DateTime(y, m, d)`, sends `2026-10-01T00:00:00.000`, but local midnight doesn't exist on every day: where DST starts at midnight (`America/Santiago` 2026-09-06, `Africa/Cairo` 2026-04-24, `Asia/Beirut` and `Atlantic/Azores` 2026-03-29, `America/Havana` 2026-03-08) it is 01:00, and the server rejects `…T01:00:00.000`. So `DateOnly` builds `DateTime.utc(y, m, d)`, which sends `2026-10-01T00:00:00.000Z` on every day of the year in every zone; the `ApiDate` pattern accepts it and Pydantic's own `date` does too. Dates from the server (`"2026-10-01"`) parse to a **local** `DateTime` (01:00 on a gap day), so a server date goes back through `DateOnly.from`. Dates are compared with `DateOnly.isSameDay`/`compare`, never `==`. `.toUtc()` on a local date is a bug: in Bucharest it sends `2026-09-30T21:00:00.000Z`, which is rejected (`date_from_datetime_inexact`). `swagger_parser`'s `field_parsers` don't work with freezed, so there is no per-field converter; `DateOnly.format`/`parse` cover `YYYY-MM-DD` strings. |
| 4 | Instants are UTC with `Z` (`ApiInstant.of`) | Confirmed. `ApiInstant.of(DateTime(2026, 10, 1, 18, 30))` sends `2026-10-01T15:30:00.000Z` in Bucharest. A local `DateTime` would send no offset and get 422 (`timezone_aware`). Server instants with microseconds (`…16:00:00.123456Z`) parse to UTC `DateTime`s. |
| 5 | PUT bodies include explicit nulls | Confirmed. Only with `include_if_null: false` (decision 3): `MeUpdate(displayName: 'Ana', timezone: 'UTC')` sends `birthday`, `locale` and `avatar_url` as `null`, nested models are serialized, and `@Default` fields are sent. |
| 6 | problem+json is decoded | Confirmed. `ProblemInterceptor` turns `application/problem+json` into a `ProblemException` with `errors[]`, `request_id` and `Retry-After`. A non-problem error (an HTML 502) is `UnexpectedApiException`; connection errors and timeouts are `NetworkException`. |
| – | Unknown enum values | Confirmed. `"status": "archived"` parses to `ActivityStatus.$unknown`. |

## Consequences

- Backend changes flow as: change the code → `uv run python -m friends_api.cli export-openapi` →
  `dart run swagger_parser` in `app/` → `dart run build_runner build -d`, in the same PR.
- Every `DateTime` put into a request goes through `ApiInstant.of` (instants) or `DateOnly`
  (calendar dates). Reviews check this; the spike tests show both shapes.
- Screens catch `ApiException` (usually via `ServerErrorsMixin`/`FieldErrors` for forms and
  `AsyncValueView`/`friendlyErrorMessage` elsewhere) and branch on `ProblemException.code`, never on
  `detail`.
- Every data provider watches `currentUserIdProvider`, so cached data resets on logout and when
  another account signs in.
- Tests use `test/helpers/fake_http_adapter.dart` (a scripted `HttpClientAdapter`) and
  `test/helpers/test_backend.dart` (the real network and auth stack wired to it); no
  http_mock_adapter.
- Upgrading swagger_parser means re-running the spike (`app/test/core/api/spike/README.md`): its
  `include_if_null` semantics have changed between versions before.
