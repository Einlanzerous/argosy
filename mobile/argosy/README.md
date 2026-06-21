# Argosy — mobile client (Flutter)

The Android + iOS client for Argosy. Streaming-only MVP; Android is the
primary, validated target (iOS builds but is theory-only for now). See the
epic **ARGY-7** (Phase 6) and the player spike **ARGY-77**.

## Toolchain (pinned)

- **Flutter 3.44.2** (stable) / **Dart 3.12.2**
- Installed user-local under `~/dev-tools`; activate with:
  ```sh
  source ~/dev-tools/env.sh
  ```
- The dev phone connects over **wireless adb** (`adb pair` / `adb connect`).

## Run

```sh
source ~/dev-tools/env.sh
cd mobile/argosy
flutter pub get
flutter run            # or: flutter build apk --debug
flutter analyze        # lints (treats unused imports as errors)
flutter test           # widget smoke test
```

## Stack

- **State / DI:** Riverpod (`flutter_riverpod`)
- **Routing:** `go_router`, gated on auth state (`splash → login → home`)
- **HTTP:** `http` (the generated Dart API client lands in ARGY-78)

## Layout

```
lib/
  main.dart            ProviderScope → ArgosyApp
  app.dart             MaterialApp.router + Argosy theme
  router/              go_router config + auth-gate redirect
  theme/               brass-on-charcoal design tokens, ThemeData, ThemeExtension
  widgets/             shared UI — poster card, media rail, chips, hatch, mark
  features/
    splash/            bootstrap splash
    auth/              auth controller (placeholder) + login gate
    home/              home placeholder (showcases the design system)
assets/
  fonts/               Archivo + Hanken Grotesk (variable TTFs, bundled)
  brand/               Argosy ship mark (logo-only, transparent)
```

## Design language

A direct port of the web design tokens (`web/src/style.css`) — brass-on-charcoal,
mercantile. Background `#171717`, brass accent `#c99a4e`, cream ink `#eaeae5`;
**Archivo** for display, **Hanken Grotesk** for body. Tokens that don't fit
Material's `ColorScheme` live in the `ArgosyTokens` theme extension
(`context.argosy`).

## Status (ARGY-45)

Scaffold only: theme, navigation, state wiring, and a runnable
`splash → auth gate → home placeholder` skeleton. Auth and the home rows are
placeholders — real device pairing is **ARGY-46**, the API client **ARGY-78**,
browse/home **ARGY-47**, and the player screen **ARGY-79**.
