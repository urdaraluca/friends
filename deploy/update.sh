#!/bin/sh
# Pull the image tagged FRIENDS_TAG (see .env) and restart. Migrations run on start-up,
# after an automatic pre-migration backup in BACKUP_HOST_DIR.
set -eu
cd "$(dirname "$0")"
docker compose pull backend
docker compose up -d backend
docker image prune -f
docker compose ps
