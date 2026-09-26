# Contributing

How work gets into `main`. Setup is in the [README](README.md); the API rules are in
[`docs/api/contract.md`](docs/api/contract.md) and the decisions behind them in [`docs/adr/`](docs/adr/).

## Milestone flow: branch → PR → CI green → squash-merge

Work is planned as GitHub issues, one per milestone and side (`M5 · Backend: …`, `M5 · App: …`), in
the `MVP` milestone.

1. **Branch** from an up-to-date `main`, one branch per issue (or per coherent part of a big one):
   ```sh
   git switch main
   git pull
   git switch -c m5-web-hosting        # m<N>-<topic>; or fix/…, ci/…, docs/…
   ```
2. **Commit** in small steps. Run the [local checks](#local-checks) for the side you touched before
   pushing, so CI is a confirmation rather than a debugger.
3. **Open a PR** against `main`. Put `Closes #<issue>` (or `Part of #<issue>`) in the description, and
   say what changed in the contract, an ADR or the deploy steps, if anything.
4. **Wait for CI to be green.** Only the workflows for the parts you touched run (see below). Fix
   forward on the branch; don't merge on red.
5. **Squash-merge**, so `main` gets one commit per PR. The PR title becomes the commit subject, e.g.
   `M5: serve the web app from the API container`. Delete the branch afterwards.

**Contract first.** When the API changes, `docs/api/contract.md`, the code, `backend/openapi.json` and
the generated Dart client change in the **same PR**:
```sh
# in backend/
uv run python -m friends_api.cli export-openapi   # writes backend/openapi.json
# in app/
dart run swagger_parser                           # updates lib/core/api/generated
dart run build_runner build -d                    # *.g.dart / *.freezed.dart (not committed)
```
Commit `backend/openapi.json` and `app/lib/core/api/generated/`. CI fails if either is stale.
swagger_parser never deletes files, so when an endpoint or schema goes away, delete
`app/lib/core/api/generated/` before running it (then run build_runner again); CI regenerates into an
empty directory and fails on leftovers.

### What CI runs

Workflows are path-filtered. A change that only touches Markdown files (`*.md`) runs none of them.

| Workflow | Runs for changes to | Checks |
|---|---|---|
| `backend-ci` | `backend/**` | ruff, format, mypy (strict), pytest with the 80 % coverage gate, `alembic upgrade head && alembic check`, `openapi.json` is up to date |
| `app-ci` | `app/**`, `backend/openapi.json` | generated client matches `openapi.json`, format, `flutter analyze --fatal-infos`, `flutter test`, web and Android debug builds (iOS: run it manually with `build_ios=true`) |
| `backend-image` | PRs: the Dockerfile, backend dependencies, `app/**`. `main`: `backend/**`, `app/**`. Tags `backend-v*` | Flutter web build (x64), `linux/arm64` image with the web app inside, smoke test of the local image; only then pushes to GHCR (from `main` and tags) |

If you turn on branch protection, don't make these workflows **required** checks: a path-filtered
workflow that never runs keeps the PR blocked forever.

## Local checks

**Backend** (from `backend/`):
```sh
uv sync
uv run ruff check .
uv run ruff format --check .        # `uv run ruff format .` fixes it
uv run mypy
uv run pytest --cov                 # coverage must stay >= 80 %
uv run python -m friends_api.cli export-openapi   # then: git diff --exit-code openapi.json
```
Migrations must match the models (CI runs this on a scratch database):
```powershell
$env:DATABASE_URL = "sqlite:///./ci.db"; uv run alembic upgrade head; uv run alembic check
Remove-Item Env:DATABASE_URL; Remove-Item ci.db*
```
In Git Bash: `DATABASE_URL=sqlite:///./ci.db uv run alembic upgrade head && DATABASE_URL=sqlite:///./ci.db uv run alembic check; rm -f ci.db*`.

**App** (from `app/`):
```sh
flutter pub get
dart run swagger_parser             # must leave lib/core/api/generated unchanged (git status)
dart run build_runner build -d
flutter analyze --fatal-infos
flutter test
```
Format the hand-written code only (`git add` new files first, so the list includes them):
```powershell
dart format (git ls-files 'lib/*.dart' 'test/*.dart' ':!lib/core/api/generated')    # PowerShell
dart format $(git ls-files 'lib/*.dart' 'test/*.dart' ':!lib/core/api/generated')   # Git Bash
```
Don't run `dart format` on `lib/core/api/generated/` (so not a plain `dart format lib test`): CI
compares it with the raw `dart run swagger_parser` output. If you did, run `dart run swagger_parser`
again to restore it.

**Docker image** (optional, needs Docker Desktop), from the repo root:
```sh
docker build -t friends-backend:local backend        # API only: no web app inside
# With the web app, like CI (the named context replaces the Dockerfile's `web` stage). First, in app/:
#   flutter build web --release --no-web-resources-cdn --dart-define-from-file=env/prod.json
docker build -t friends-backend:local --build-context web=app/build/web backend
# Run it (throwaway database), then open http://localhost:8000/ and http://localhost:8000/api/v1/health
docker run --rm -p 8000:8000 -e JWT_SECRET=local-only-secret-at-least-32-bytes -e PUBLIC_APP_URL=https://friends.example.com friends-backend:local
```

## Windows quirks

- Turn on **Developer Mode** (Flutter plugins need symlinks) and **Windows Hypervisor Platform**
  (Android emulator), and run `git config --global core.longpaths true` (Gradle and
  `.claude/worktrees/…` paths get long).
- Line endings: `.gitattributes` checks text files out with LF whatever `core.autocrlf` says
  (`*.bat`, `*.cmd` and `*.ps1` excepted), because `dart format` and the Linux containers expect LF.
  `.editorconfig` tells editors the same; keep LF when you save.
- You don't need a system Python: uv installs 3.14, so use `uv run python …` from `backend/`.
  `python`/`python3` in a Windows shell is often just the Microsoft Store alias.
- In `cmd`, `>` is a redirect, so an unquoted version specifier like `pkg>=1.0` writes a file named
  `=1.0`. Use PowerShell or Git Bash, or quote it.
- PowerShell sets environment variables with `$env:NAME = "value"`; the `NAME=value command` form
  only works in Git Bash.
- **Claude desktop app** (sandboxed MSIX): writes under `%APPDATA%` are virtualized, which breaks
  uv's managed Python links. Before running uv there:
  ```powershell
  $env:UV_PYTHON_INSTALL_DIR = "C:\Users\<you>\develop\uv-python"
  $env:PATH = "$env:LOCALAPPDATA\Microsoft\WinGet\Links;C:\Users\<you>\develop\flutter\bin;$env:PATH"
  ```
- Android emulator: run `adb reverse tcp:8000 tcp:8000` and keep `env/dev.json`, or use
  `env/dev.emulator.json` (API on `10.0.2.2:8000`).
