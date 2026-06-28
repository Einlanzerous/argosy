# Android release signing & distribution

`mobile-release.yml` builds a **signed** APK + AAB on every `v*` tag (the tags
release-please cuts), attaches the APK to that GitHub Release, and — once a Play
service account is configured — pushes the AAB to the Play **internal** track.

Release builds are signed with an **upload keystore** read from
`android/key.properties` (gitignored). When that file is absent (local dev, CI
debug builds) the build falls back to the debug key, so `flutter run --release`
still works — see `app/build.gradle.kts`.

## One-time: create the upload keystore

```sh
keytool -genkeypair -v \
  -keystore upload-keystore.jks -storetype PKCS12 \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

The default keystore type is **PKCS12**, which uses a single password for the
store *and* the key — `keytool` ignores a separate `-keypass`. So
`storePassword` and `keyPassword` are the same value (and the
`ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_PASSWORD` secrets below are identical).

Keep `upload-keystore.jks` **somewhere safe and private** (a password manager /
secrets vault). Never commit it — `**/*.jks` and `key.properties` are already
gitignored. This is the **upload** key, not the app signing key: with Play App
Signing (enrolled on first release) Google holds the real signing key, so a lost
upload key is recoverable by resetting it in the Play Console — but still treat
it as a secret.

### Local release builds

Create `android/key.properties` (next to `app/`) pointing at the keystore:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=********
keyAlias=upload
keyPassword=********
```

Then `flutter build apk --release` / `flutter build appbundle --release`.

## GitHub secrets (Repo → Settings → Secrets and variables → Actions)

Required for the signed Android build:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` (the keystore, base64-encoded) |
| `ANDROID_KEYSTORE_PASSWORD` | the `storePassword` |
| `ANDROID_KEY_ALIAS` | the alias (`upload` above) |
| `ANDROID_KEY_PASSWORD` | same value as `ANDROID_KEYSTORE_PASSWORD` (PKCS12) |

The workflow decodes the keystore to `android/app/upload-keystore.jks` and
writes `android/key.properties` at build time. Without `ANDROID_KEYSTORE_BASE64`
the Android release job fails fast with a pointer here.

Set them in one shot with `gh` (run from the repo root):

```sh
base64 -w0 upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
printf '%s' "$STOREPASS" | gh secret set ANDROID_KEYSTORE_PASSWORD
printf '%s' "upload"     | gh secret set ANDROID_KEY_ALIAS
printf '%s' "$STOREPASS" | gh secret set ANDROID_KEY_PASSWORD
```

## How a release triggers the build

release-please cuts the `v*` tag using the default `GITHUB_TOKEN`, and GitHub
won't fire `on: push: tags` workflows for token-pushed tags. So `mobile-release`
is a **reusable workflow** invoked by `release-please.yml` (gated on
`releases_created`) in the same push-to-main run. Two other entrypoints exist:

- **Manual:** Actions → *mobile-release* → *Run workflow* → `tag: v0.8.1` —
  rebuilds + re-attaches a signed artifact for any existing tag without cutting a
  release (and without touching the server image in `publish.yml`).
- **Hand-pushed tag:** a `v*` tag pushed with user creds (not `GITHUB_TOKEN`)
  still fires the legacy `push: tags` trigger.

## Play Store internal track

The AAB → Play internal-track step is **skipped** unless
`PLAY_SERVICE_ACCOUNT_JSON` is set, so the signed GitHub-Release APK works on its
own. The browser steps below are one-time and can only be done by the Play
Developer account owner.

### A. Create the app (Play Console)

1. <https://play.google.com/console> → **Create app**. App name *Argosy*, type
   *App*, **Free**, accept the declarations.
2. **Set up your app** → work through the required tasks: privacy policy URL, app
   access (mark the household login as test creds or all-access), ads (none),
   content rating questionnaire, target audience, data safety, government-apps =
   no. These gate even internal testing.
3. The package name `dev.dodson.argosy` is claimed by the **first uploaded AAB**
   (next step) — there's no separate "register package" action.

### B. First AAB upload (manual — Google requires it)

1. **Testing → Internal testing → Create new release**.
2. On the first release Play offers **Play App Signing** — **accept it** (Google
   manages the app signing key; our `upload-keystore.jks` stays the upload key).
3. Upload the AAB built with the upload key:
   `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`.
4. Add a release name / notes, **Save → Review → Start rollout to Internal
   testing**. Add testers (your Google account) under the *Testers* tab and use
   the opt-in link to install.

### C. Service account → enable CI auto-upload

1. **Play Console → Setup → API access** → create a new Google Cloud project (or
   link one) → **Create service account**. This opens Google Cloud Console.
2. In Cloud Console create the service account (no roles needed there), then back
   in Play Console **grant access** with the *Release to testing tracks*
   permission (Account permissions → Releases).
3. Service account → **Keys → Add key → JSON** → download.
4. Add the JSON file's **full contents** as the repo secret:
   `gh secret set PLAY_SERVICE_ACCOUNT_JSON < service-account.json`.

Once `PLAY_SERVICE_ACCOUNT_JSON` is set, every release-please release uploads the
AAB to the internal track automatically (`r0adkll/upload-google-play`). Promote
internal → closed → production from the Play Console when ready.

## Versioning

`versionName` comes from the tag (`v0.4.0` → `0.4.0`); `versionCode` is the CI
run number (monotonic, as Play requires). pubspec stays `0.1.0+1` as the dev
default — the tag is the source of truth for released builds.
