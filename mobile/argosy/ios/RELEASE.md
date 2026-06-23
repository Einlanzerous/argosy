# iOS signing & TestFlight runbook

The `ios` job in `mobile-release.yml` is **stubbed**: it no-ops until the Apple
secrets below exist (so we don't burn macOS minutes or block Android). On-device
iOS verification is tracked separately as **ARGY-82**.

None of this is Flutter-specific — it's the standard Apple distribution dance,
and it can't be automated away. Do the portal steps once on a Mac with Xcode.

## Prerequisites (manual, one-time)

1. **Apple Developer Program** membership ($99/yr).
2. **App record**: App Store Connect → create an app with bundle id
   `dev.dodson.argosy` (must match `ios/Runner.xcodeproj` — set it in Xcode →
   Signing & Capabilities, and pick the team).
3. **Signing assets** — easiest is [fastlane match](https://docs.fastlane.tools/actions/match/):
   a private git repo holding the encrypted distribution certificate +
   App Store provisioning profile. Alternatively create them by hand in the
   Developer portal and export the `.p12` + `.mobileprovision`.
4. **App Store Connect API key**: Users and Access → Integrations → App Store
   Connect API → generate a key (Admin/App Manager). Note the **Key ID**,
   **Issuer ID**, and download the `.p8` once.

## GitHub secrets to enable the job

| Secret | Source |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | API key ID (presence flips the job on) |
| `APP_STORE_CONNECT_ISSUER_ID` | API key issuer ID |
| `APP_STORE_CONNECT_API_KEY` | contents of the `.p8` |
| `MATCH_GIT_URL` / `MATCH_PASSWORD` | if using fastlane match |

## Finishing the workflow (when the account exists)

Replace the placeholder step in the `ios` job with, roughly:

```sh
# fastlane match appstore --readonly     # fetch certs/profiles
flutter build ipa --release \
  --build-name="$NAME" --build-number="$CODE" \
  --export-options-plist=ios/ExportOptions.plist
# then upload, e.g. apple-actions/upload-testflight-build with the ASC API key,
# or `fastlane pilot upload --ipa build/ios/ipa/*.ipa`
```

The Info.plist already declares `UIBackgroundModes: [audio]` (ARGY-50). Confirm
the export method is `app-store` and the team/bundle id match the app record.
