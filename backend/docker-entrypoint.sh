#!/bin/sh
set -eu
if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  # Backs up the database first when migrations are pending, then upgrades to head.
  python -m friends_api.cli migrate
fi
exec "$@"
