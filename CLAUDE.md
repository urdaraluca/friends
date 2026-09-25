# Friends monorepo: notes for Claude

- **Stack:**
  - `backend/`: FastAPI, sync SQLAlchemy, SQLite, Python 3.14, uv. The package is `friends_api`.
  - `app/`: Flutter 3.47 / Dart 3.13, with Riverpod 3 (codegen), go_router 18, dio, and
    `material_ui` (not `package:flutter/material.dart`).
- **Source of truth for API behaviour:** `docs/api/contract.md`. Architecture decisions are in
  `docs/adr/`.

## Commands

Backend (run from `backend/`):
- `uv sync`
- `uv run pytest`
- `uv run ruff check .`, `uv run ruff format .`
- `uv run mypy` (strict)
- Dev server: `uv run uvicorn friends_api.main:create_app --factory --reload --port 8000`

App (run from `app/`):
- `flutter pub get`
- `dart run build_runner build -d` (generated `*.g.dart` and `*.freezed.dart` are gitignored)
- `flutter analyze --fatal-infos`
- `dart format lib test`
- `flutter test`
- Web dev run: `flutter run -d chrome --web-port 5000 --dart-define-from-file=env/dev.json`

## Conventions

**Backend**
- Endpoints that touch the DB are plain `def`, not `async def`.
- Routers stay thin; services take a `Session`, raise `AppError`s, and never import FastAPI.
- Every router has exactly one tag. The operationId is the handler name, and that name becomes the
  generated Dart method name.
- Timestamps are timezone-aware UTC. Ruff `DTZ` enforces this, so never use naive datetimes.

**App**
- Dart 3.13 constructor syntax: `const new({super.key});` and `factory fromJson(...)`. Run
  `dart fix --apply` if the analyzer flags `unnecessary_type_name_in_constructor`.
- Import `package:material_ui/material_ui.dart`, never `package:flutter/material.dart`.

## Environment quirks (Windows + Claude desktop app)

- The desktop app runs sandboxed (MSIX), so writes under `%APPDATA%` are virtualized. This breaks
  uv's managed Python junctions. Before running uv from this environment:
  - set `UV_PYTHON_INSTALL_DIR=C:\Users\Raluca\develop\uv-python`
  - put `C:\Users\Raluca\AppData\Local\Microsoft\WinGet\Links` (uv) and
    `C:\Users\Raluca\develop\flutter\bin` on PATH
- In cmd, don't pass version specifiers like `pkg>=1.0` unquoted: `>` is treated as a redirect.
  Use bash or PowerShell.
