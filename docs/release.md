# Releasing the Android beta (issue #14)

The code side is in place:
- release signing from `key.properties` or CI secrets;
- App Links for `https://<host>/join/<code>`;
- the `app-release` workflow, the app icon and splash screens, and a privacy page at `/privacy.html`.

What's left needs the owner's accounts and decisions. It depends on the Pi deploy
([`deploy/README.md`](../deploy/README.md), issue #1).

## 1. Decisions

- **App ID:** `io.github.urdaraluca.friends`. It can't change once the app is in a store.
- **Public hostname:** the origin the Pi serves, e.g. `https://friends.example.com`.
  - The web app is served from that origin and keeps `API_BASE_URL=""` (`app/env/prod.json`).
  - Mobile builds get the origin from the `API_BASE_URL` repository variable, and the `app-release` workflow writes `env/prod.mobile.json` from it.
- **Privacy page:** `app/web/privacy.html` is a draft. Read it, adjust the contact line, and it's served at `https://<host>/privacy.html`.

## 2. Signing

Generate the upload/release keystore once. **Never commit it.** Back it up outside the repo (a
password manager). Losing it means the installed app can never be updated.

```sh
keytool -genkeypair -v -keystore friends-release.jks -alias friends \
  -keyalg RSA -keysize 4096 -validity 10000
```

**Local release builds:** create `app/android/key.properties`. It is gitignored, like `*.jks`.

```properties
storeFile=C:/path/to/friends-release.jks
storePassword=...
keyAlias=friends
keyPassword=...
```

Without it, release builds fall back to the debug key and print a warning. Such an APK can't update a
properly signed one.

**CI** (Settings → Secrets and variables → Actions):

| Kind | Name | Value |
|---|---|---|
| secret | `ANDROID_KEYSTORE_BASE64` | `base64 -w0 friends-release.jks` (PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("friends-release.jks"))`) |
| secret | `ANDROID_KEYSTORE_PASSWORD` | the store password |
| secret | `ANDROID_KEY_ALIAS` | `friends` |
| secret | `ANDROID_KEY_PASSWORD` | the key password |
| variable | `API_BASE_URL` | `https://<host>` |
| variable | `APP_LINK_HOST` | optional; defaults to the host of `API_BASE_URL` |

## 3. App Links (invite links open the app)

1. Get the signing certificate's SHA-256. Either:
   - run `keytool -list -v -keystore friends-release.jks -alias friends`;
   - or read the "Signing certificate" line of an `app-release` run.
2. On the Pi, put it in `.env` as `ANDROID_CERT_SHA256=AA:BB:…`. To keep debug builds working, add the debug fingerprint after a comma.
3. Restart with `./update.sh`.
4. Check that `https://<host>/.well-known/assetlinks.json` lists the fingerprint.
5. After installing the release APK:

   ```sh
   adb shell pm get-app-links io.github.urdaraluca.friends   # expect: verified
   adb shell am start -a android.intent.action.VIEW -d "https://<host>/join/ABCDEFGHJK"
   ```

   The second command should open the join screen in the app.

## 4. Release

1. Tag the backend and deploy it: `git tag backend-v0.2.0 && git push origin backend-v0.2.0`. Then set `FRIENDS_TAG` on the Pi and run `./update.sh`.
2. Bump `version:` in `app/pubspec.yaml` if needed. Then tag the app: `git tag app-v0.1.0 && git push origin app-v0.1.0`.
   - The `app-release` workflow builds the signed APK and publishes a GitHub Release with it attached.
   - The release notes come from [`release-notes-android.md`](release-notes-android.md).
3. Run the beta checklist on real devices:
   - register through an invite link;
   - create a group, and add movies with IMDb ratings;
   - spin the wheel, vote in a poll, schedule a weekly event;
   - check the calendar and the birthdays;
   - log out everywhere, then delete a test account.
4. Collect feedback in new issues.

## iOS

Compile-only until there is a Mac and an Apple Developer account (issue #18). Once there is:
- serve `apple-app-site-association` like `assetlinks.json`;
- add the Associated Domains entitlement.
