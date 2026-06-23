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
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Keep `upload-keystore.jks` **somewhere safe and private** (a password manager /
secrets vault). If it's lost you can't ship updates under the same identity.
Never commit it — `**/*.jks` and `key.properties` are already gitignored.

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
| `ANDROID_KEY_PASSWORD` | the `keyPassword` |

The workflow decodes the keystore to `android/app/upload-keystore.jks` and
writes `android/key.properties` at build time. Without `ANDROID_KEYSTORE_BASE64`
the Android release job fails fast with a pointer here.

## Play Store internal track (optional)

The AAB → Play internal-track step is **skipped** unless
`PLAY_SERVICE_ACCOUNT_JSON` is set, so the GitHub-Release APK works on its own.

To enable it:

1. Create a Google Play Developer account ($25 one-time) and the app listing for
   `dev.dodson.argosy`.
2. In Play Console → Setup → API access, create / link a **service account** with
   the *Release to testing tracks* permission; download its JSON key.
3. Add the JSON file's full contents as the `PLAY_SERVICE_ACCOUNT_JSON` secret.
4. The **first** AAB must be uploaded manually via the Play Console (Google
   requires the initial release by hand); subsequent tags upload automatically.

## Versioning

`versionName` comes from the tag (`v0.4.0` → `0.4.0`); `versionCode` is the CI
run number (monotonic, as Play requires). pubspec stays `0.1.0+1` as the dev
default — the tag is the source of truth for released builds.
