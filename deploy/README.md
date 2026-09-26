# Deploying Friends on the Raspberry Pi

**Where things live**
- GitHub Actions builds `ghcr.io/urdaraluca/friends-backend` for `linux/arm64` and the Pi pulls it.
- One container, one origin: it serves the API under `/api/v1`, the Flutter web app at `/` (deep
  links such as invite links `/join/<code>` included) and `/.well-known/assetlinks.json`.
  CI builds the web app into the image, so there is nothing else to deploy.
- Data lives in the Docker volume `friends-data`, as `/data/friends.db` (SQLite, WAL mode).

**Image tags**

| Tag | Built from |
|---|---|
| `main` | the tip of `main` |
| `sha-abc1234` | an exact commit |
| `0.1.0`, `0.1` | release tag `backend-v0.1.0` |
| `latest` | the newest release |

## First-time setup

1. **Docker.** Check that Docker Engine and the compose plugin are installed: `docker compose version`.
   If they aren't, follow the official Debian / Raspberry Pi OS instructions on docs.docker.com.

2. **Folders.** Create them. The container runs as uid 10001.
   ```sh
   sudo install -d /srv/friends
   sudo install -d -o 10001 -g 10001 /srv/friends/backups   # or mount a USB drive / NAS share here
   ```

3. **Files.** Copy `docker-compose.yml`, `update.sh` and `.env.example` from this folder into
   `/srv/friends`:
   ```sh
   cd /srv/friends
   for f in docker-compose.yml update.sh .env.example; do
     curl -fsSLO "https://raw.githubusercontent.com/urdaraluca/friends/main/deploy/$f"
   done
   chmod +x update.sh
   cp .env.example .env && chmod 600 .env
   ```
   Then fill in `JWT_SECRET` and `PUBLIC_APP_URL` in `.env`, and pin `FRIENDS_TAG` to a release.

4. **Package visibility.** After the first image push, open GitHub → your profile → Packages →
   `friends-backend` → Package settings → Change visibility → **Public**. The repo is public and the
   image contains no secrets.
   - Prefer to keep it private? Then log the Pi in with a **classic** PAT that has only the
     `read:packages` scope (GHCR doesn't reliably support fine-grained tokens):
     ```sh
     echo "$PAT" | docker login ghcr.io -u urdaraluca --password-stdin
     ```

5. **Clock sync.** The Pi has no real-time clock. Make Docker wait for NTP, otherwise tokens are
   issued with wrong timestamps right after boot:
   ```sh
   sudo systemctl enable --now systemd-time-wait-sync
   sudo mkdir -p /etc/systemd/system/docker.service.d
   printf '[Unit]\nAfter=time-sync.target\nWants=time-sync.target\n' | \
     sudo tee /etc/systemd/system/docker.service.d/10-time-sync.conf
   sudo systemctl daemon-reload
   ```

6. **Start it.**
   ```sh
   ./update.sh                      # pull + up -d; migrations run automatically on start
   docker compose ps                # STATUS shows "(healthy)" after ~30 s
   curl -fsS http://127.0.0.1:8000/api/v1/health
   ```

7. **Proxy.** Point the existing reverse proxy / tunnel at `http://127.0.0.1:8000` and forward
   **every path** to it, unchanged: `/` and any deep link (`/join/…`, `/groups/…`), `/api/…` and
   `/.well-known/…`. The container decides what each path is (contract section 1.1):
   - don't limit the proxy to `/api`, and don't strip or rewrite path prefixes;
   - don't serve your own error pages or an `index.html` fallback in front of it: unknown `/api/…`
     paths must reach the app as a problem+json 404, never HTML;
   - keep the `Cache-Control` headers the app sends: `no-cache` on everything from the web app,
     `no-store` on the API. Don't add a cache lifetime of your own (e.g. a CDN's default browser
     TTL for `.js` files): the Flutter build's file names (`main.dart.js`, `canvaskit/…`) don't
     change between releases, so a new release shows up on the next reload only because browsers
     revalidate every file (a cheap 304 when it hasn't changed);
   - keep the security headers the app sends on the web app (`Content-Security-Policy`,
     `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`; contract section 1.1). A
     proxy that adds its own CSP must allow at least the same sources, or the app won't start;
   - pass `X-Forwarded-For` / `X-Forwarded-Proto` (uvicorn trusts them, see `FORWARDED_ALLOW_IPS`).

   Then check from outside, e.g. from a phone on mobile data:
   ```sh
   curl -fsS https://<your-host>/api/v1/health
   curl -fsS https://<your-host>/join/ABCDEFGHJK | grep -q flutter_bootstrap && echo "web app ok"
   curl -s -o /dev/null -w "%{http_code}\n" https://<your-host>/api/v1/nope   # 404 (problem+json)
   ```
   Open `https://<your-host>/` in a browser: the web app talks to the API on the same origin, so
   `CORS_ORIGINS` stays empty.

8. **Nightly backups.** Add a cron entry (`crontab -e`):
   ```cron
   15 3 * * * cd /srv/friends && docker compose exec -T backend python -m friends_api.cli backup --keep 14 >> /srv/friends/backup.log 2>&1
   ```
   Backups are consistent even while the app is writing, integrity-checked and gzipped. They go to
   `BACKUP_HOST_DIR`, which should be a USB drive or NAS, not the SD card.

## Android App Links (`ANDROID_CERT_SHA256`)

Invite links open the Android app directly once Android can verify that the app and the host belong
together. Android fetches `https://<your-host>/.well-known/assetlinks.json`, which the container
builds from `ANDROID_CERT_SHA256` for the package `io.github.urdaraluca.friends`. This is used by the
Android release milestone (M10); until then, leave it empty and the file is a 404.

1. Get the SHA-256 fingerprint of each signing certificate, in the `AA:BB:…` form (32 pairs):
   - a keystore you sign release APKs with yourself:
     `keytool -list -v -keystore release.jks -alias <alias>`, line `SHA256:`;
   - with Play App Signing, the **app signing key** fingerprint from Play Console → your app →
     App integrity → App signing (installed apps are signed with that key, not the upload key);
   - optionally the debug key, so debug builds verify too:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`.
2. Put them in `.env`, comma-separated, then run `./update.sh`:
   ```sh
   ANDROID_CERT_SHA256=14:6D:E9:…:44:E5,AB:CD:…:89
   ```
3. Check it (it must be a 200 with `application/json`, and no redirect):
   ```sh
   curl -fsS https://<your-host>/.well-known/assetlinks.json
   ```

## Updating

```sh
cd /srv/friends
# bump FRIENDS_TAG in .env (e.g. 0.2.0), then:
./update.sh
```

On start-up the container takes a `pre-migrate-*.db.gz` backup whenever migrations are pending.

## Rolling back

Migrations only go forward. To go back to the previous release:
1. Set `FRIENDS_TAG` back to the previous tag.
2. Restore the matching `pre-migrate-*` backup (see below).

## Restoring a backup (practise this once)

```sh
cd /srv/friends
docker compose stop backend
BACKUP=backups/friends-20260925T031500Z.db.gz        # pick one
gunzip -c "$BACKUP" > /tmp/friends.db
docker compose run --rm --no-deps -v /tmp/friends.db:/restore/friends.db:ro --entrypoint sh backend \
  -c 'rm -f /data/friends.db-wal /data/friends.db-shm && cp /restore/friends.db /data/friends.db'
docker compose start backend
curl -fsS http://127.0.0.1:8000/api/v1/health
rm /tmp/friends.db
```

## Useful commands

```sh
docker compose logs -f backend                                   # JSON logs with request ids
docker compose exec backend python -m friends_api.cli backup     # ad-hoc backup
docker compose exec backend python -m friends_api.cli --help
```
