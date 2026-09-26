# Friends app (Flutter)

Android, iOS and web client for the Friends API. See the [root README](../README.md) for setup.

```powershell
flutter pub get
dart run build_runner build -d          # or: dart run build_runner watch -d
flutter run -d chrome --web-port 5000 --dart-define-from-file=env/dev.json
flutter analyze --fatal-infos
flutter test
```

| Env file | Use |
|---|---|
| `env/dev.json` | Web, or Android with `adb reverse tcp:8000 tcp:8000` (API on `localhost:8000`) |
| `env/dev.emulator.json` | Android emulator without `adb reverse` (API on `10.0.2.2:8000`) |
| `env/prod.json` | Release builds. Empty `API_BASE_URL` = same origin (the web build is served by the backend) |

## Building on the foundation (M4)

The API client in `lib/core/api/generated/` is swagger_parser output: regenerate it with
`dart run swagger_parser` after `backend/openapi.json` changes, and never edit or `dart format` it.
[ADR 0003](../docs/adr/0003-client-codegen.md) explains the setup and the wire rules.

| Need | Use |
|---|---|
| Call the API | `ref.watch(groupsClientProvider)` (one provider per tag in `core/api/api_providers.dart`; public endpoints use the `public…` providers on the bare Dio), wrapped in `apiCall(...)` so failures are `ApiException`s |
| Cache data per user | Every data provider does `ref.watch(currentUserIdProvider)` (`core/auth/auth_controller.dart`), so it resets on logout and account switch |
| Show loading / error + Retry / data | `AsyncValueView` (`core/widgets/async_value_view.dart`) |
| Explain an error | `friendlyErrorMessage(error, messages: {...})` (`core/api/api_error_messages.dart`); branch on `ProblemException.code` with `ErrorCodes` |
| Put 422 `errors[].field` on form fields | `ServerErrorsMixin` / `FieldErrors` (`core/forms/field_errors.dart`), with `Validators` for client-side checks |
| Send a date / an instant | `DateOnly.of(y, m, d)` (a UTC midnight; `DateOnly.from` for a date read from the API) / `ApiInstant.of(dateTime)` (`core/api/`) |
| Navigate | `Routes` path builders (`core/router/routes.dart`); add routes in `core/router/app_router.dart` |
| Invite codes | `InviteCode.parse` (any spelling or a pasted `…/join/<code>` link) |
| Test against the real network stack | `TestBackend` + `FakeHttpClientAdapter` (`test/helpers/`); `FakeAuthController` for router and screen tests |
