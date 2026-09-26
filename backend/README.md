# Friends API (FastAPI)

Python 3.14 + FastAPI + SQLite, managed with [uv](https://docs.astral.sh/uv/). See the [root README](../README.md) for setup.

```powershell
uv sync                                   # creates .venv with the dev tools
uv run uvicorn friends_api.main:create_app --factory --reload --port 8000
uv run pytest
uv run ruff check . ; uv run ruff format . ; uv run mypy
uv run python -m friends_api.cli seed-demo   # demo1..3@example.com, a group, ~120 activities (not in prod)
```

Swagger UI (dev only): http://127.0.0.1:8000/api/v1/docs
