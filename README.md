# Friends

> Group chats are where great plans go to die.
> Turn "we should do that sometime" into actual memory-making.

Friends is an app for planning activities with your friend groups:
- a shared backlog of ideas
- a calendar for birthdays, one-off plans and recurring activities
- polls inside activities
- a "what should we do?" wheel for when nobody can decide

The original product notes are in [`specs.txt`](specs.txt).

## Repository layout

| Path | What |
|---|---|
| [`app/`](app/) | Flutter app for Android, iOS and web (Riverpod, go_router, dio) |
| [`backend/`](backend/) | FastAPI + SQLite API (Python 3.14, uv) |
| [`deploy/`](deploy/) | Docker Compose setup and runbook for the Raspberry Pi |
| [`docs/`](docs/) | API contract, ADRs |
| [`.github/`](.github/) | CI (path-filtered per project) and the arm64 image build |

## Getting started on Windows

**Tools**
```powershell
winget install --id=astral-sh.uv -e      # Python toolchain (installs Python 3.14 on demand)
# Flutter 3.47.5: https://docs.flutter.dev/get-started/install/windows (add flutter\bin to PATH)
winget install Google.AndroidStudio       # Android SDK + emulator (optional for web-only work)
git config --global core.longpaths true
```

In Windows settings, also turn on:
- **Developer Mode** (Flutter plugins need symlinks)
- **Windows Hypervisor Platform** (Android emulator)

**Backend**
```powershell
cd backend
uv sync
uv run uvicorn friends_api.main:create_app --factory --reload --port 8000
```

**App** (in a second terminal)
```powershell
cd app
flutter pub get
dart run build_runner build -d
flutter run -d chrome --web-port 5000 --dart-define-from-file=env/dev.json
```

On the Android emulator, run `adb reverse tcp:8000 tcp:8000` and keep `env/dev.json`. Alternatively, use `env/dev.emulator.json`.

## Checks (what CI runs)

```powershell
cd backend; uv run ruff check .; uv run ruff format --check .; uv run mypy; uv run pytest
cd app; flutter analyze --fatal-infos; dart format --output=none --set-exit-if-changed lib test; flutter test
```
