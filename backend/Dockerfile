# syntax=docker/dockerfile:1
# Friends API image. Built natively for linux/arm64 in CI (Raspberry Pi 4/5); also builds on amd64.
FROM ghcr.io/astral-sh/uv:0.12.19 AS uv

# The Flutter web build, served at / from /app/web (contract section 1.1). CI replaces this stage
# with the real build through a named context: `--build-context web=<app/build/web>`
# (docker/build-push-action `build-contexts: web=./web-dist`). A named context overrides the stage
# of the same name.
# Without it (a plain `docker build`), /app/web gets only this marker file: there is no index.html,
# so the image serves the API alone. The stage is deliberately not empty: it doesn't rely on how
# BuildKit copies "/" out of a completely empty scratch stage.
FROM scratch AS web
COPY <<EOF /NO_WEB_BUILD.txt
Built without the Flutter web app. CI passes it with --build-context web=<app/build/web>.
EOF

FROM python:3.14.7-slim-trixie AS builder
COPY --from=uv /uv /uvx /bin/
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=0 UV_NO_DEV=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /src
# Wheels only (--no-build): fail fast instead of compiling native code on the build machine.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=.python-version,target=.python-version \
    uv sync --locked --no-install-project --no-build

FROM python:3.14.7-slim-trixie AS runtime
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_ENV=prod \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA} \
    DATABASE_URL=sqlite:////data/friends.db \
    BACKUP_DIR=/backups \
    LOG_FORMAT=json
LABEL org.opencontainers.image.source="https://github.com/urdaraluca/friends" \
      org.opencontainers.image.title="friends-backend" \
      org.opencontainers.image.description="Friends API (FastAPI + SQLite)"
RUN groupadd --system --gid 10001 friends \
 && useradd --system --uid 10001 --gid friends --no-create-home --shell /usr/sbin/nologin friends \
 && install -d -o friends -g friends -m 0750 /data /backups
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
# Code stays root-owned: read-only for the app user.
COPY alembic.ini ./
COPY alembic ./alembic
COPY friends_api ./friends_api
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN python -m compileall -q friends_api alembic
# Last, so a new web build only changes this layer. Root-owned and read-only for the app user.
COPY --from=web / /app/web
USER friends
VOLUME ["/data"]
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["python", "-c", "import sys, urllib.request as u; sys.exit(0 if u.urlopen('http://127.0.0.1:8000/api/v1/health', timeout=3).status == 200 else 1)"]
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["uvicorn", "friends_api.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--no-access-log", "--timeout-graceful-shutdown", "10"]
