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
