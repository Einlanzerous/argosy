# ARGY-77 — Flutter player spike: decision doc

**Status:** Recommendation drafted (desk research complete). Scope set to **Android-first** (2026-06-21). **Pending:** on-device Android validation + Arin's player sign-off before the spike can close.
**Date:** 2026-06-21

This doc is the *recommendation* half of ARGY-77. The *throwaway proof* half (a `mobile/` Flutter app exercising the live `:8097` server) still needs a hands-on session with the Flutter SDK and a **real Android device** — PiP and HW HEVC cannot be validated headless. The "Validation checklist" at the end is the exact script for that session.

---

## ⚠️ Scope update (2026-06-21): Android-first, iOS in theory only

Direction set after the desk research: **ship and validate Android now; cover iOS *in theory* (keep a low-friction path) but do not build or verify it for now.** This sharpens the recommendation:

- The whole native-plugin-vs-library tension below was driven by **iOS** PiP + iOS sidecar subtitles. Drop iOS-for-now and it mostly dissolves.
- **The two server changes (S1/S2) are NOT needed for the Android MVP** — they're iOS-only. Filed as **ARGY-82** (Backlog, low) and deferred until iOS is real. Android works against the server as-is: ExoPlayer sets auth headers and accepts sidecar WebVTT.
- **media_kit is out for the MVP**: its PiP is unmerged for **both** platforms (PR #1410 covers Android 8+ *and* iOS 15+), so it can't do PiP on **Android** either — and PiP is a hard requirement on the platform we're shipping.

The "two requirements in tension," "server collision," and S1/S2 sections that follow are retained as the **iOS-future reference** (what ARGY-82 + the iOS player work will need), not MVP blockers.

## TL;DR recommendation (Android-first)

1. **Lead pick: `better_player_plus`** (v1.3.4, actively maintained, ExoPlayer/AVPlayer-backed). On **Android** it gives native PiP + background/lock-screen + HLS/ABR + sidecar-WebVTT track selection out of the box, in one Dart wrapper. It already ships an **AVPlayer iOS backend**, so iOS later is *"validate + patch,"* not *"build from scratch"* — the low-friction iOS-future path. Verify its Android PiP + subtitle behaviour in the proof.
2. **Escape hatch: a thin native Android plugin over Media3/ExoPlayer** — if `better_player_plus`'s Android PiP/subtitles disappoint in the proof. Not throwaway: it's exactly the Android half of an eventual cross-platform native plugin, and ExoPlayer Activity-PiP is rock-solid.
3. **Dropped for MVP: media_kit** (no native PiP on Android today; revisit only if PR #1410 lands and stabilises).
4. **iOS server work (S1/S2): deferred to ARGY-82.** Documented below so the iOS path is understood now, not rediscovered later.

---

## (iOS-future reference) Why iOS is hard: two requirements in direct tension

Argosy wants, on iOS, **both**:
- **Native OS-level Picture-in-Picture** — which requires an `AVPlayer`/`AVPlayerLayer` (or `AVSampleBufferDisplayLayer`) surface. Texture-rendered players (media_kit/libmpv, fvp/libmdk, VLC) cannot get native iOS video PiP without bridging into one of those. (flutter/flutter#60048, open since 2020.)
- **Sidecar WebVTT subtitles** fetched as separate URLs — which **AVPlayer natively refuses**. It only selects WebVTT delivered *inside* the HLS master playlist via `#EXT-X-MEDIA`. Overlay hacks (e.g. `better_native_video_player`) render subs in a Flutter layer that **vanishes inside the PiP window** — so they fail the requirement precisely where it matters.

The only way to satisfy both on iOS is an AVPlayer-backed surface fed subtitles it accepts natively — i.e. **subtitles delivered in the HLS manifest**, not as sidecar files.

---

## The collision with Argosy's actual server contract

Cross-referencing the two halves of this spike surfaced a blocker that neither view showed alone:

| Server fact (verified in code) | Flutter/iOS fact (verified) | Consequence |
|---|---|---|
| HLS playlist + segments require a **Bearer `Authorization` header**; **no `?token=` query fallback** (only `/stream`, `/subtitles`, `/beacon` take `?token=`). | **AVPlayer on iOS has no public API to set HTTP headers** on its HLS requests. | On iOS, AVPlayer **cannot authenticate to the transcode HLS endpoints today.** Blocks *every* AVPlayer-backed option (native plugin, better_player_plus, video_player). |
| Subtitles are served **sidecar** as `/items/{id}/subtitles/{trackId}?token=` (WebVTT), not in the manifest. | AVPlayer only takes WebVTT via `#EXT-X-MEDIA` in the manifest; sidecar/overlay subs disappear in PiP. | iOS subtitles won't work (or won't survive PiP) without a manifest change. |

### Recommended server-side changes (both small, both mirror existing patterns)

**S1 — Accept `?token=` on the transcode HLS endpoints.** `GET /api/v1/transcode/{sessionId}/*` (master, variant playlists, init, `.m4s`) should accept the device token as a query param, exactly like `/items/{id}/stream?token=` and `/subtitles?token=` already do. This removes the iOS header problem for *any* AVPlayer-backed player and costs nothing on Android (ExoPlayer can set headers, but `?token=` is simpler and uniform). **This is the load-bearing unblock — do it regardless of which player wins.**

**S2 — Inject a `#EXT-X-MEDIA` WebVTT subtitle rendition into the HLS master playlist** (when a subtitle track is requested), referencing the existing WebVTT the server already produces. Makes subtitles a native, selectable track in AVPlayer that **survives in PiP and AirPlay**. ExoPlayer doesn't need this (it takes sidecar VTT fine via `MergingMediaSource`), but doing it uniformly means one code path on the client. The transcode pipeline (Phase 3 / ARGY-4) already emits CMAF/fMP4 HLS, so this is an additive manifest change, not a re-architecture.

> If S2 is judged too costly for the MVP, the fallback is an iOS-only `AVAssetResourceLoaderDelegate` that injects the manifest entry client-side — more native glue, same outcome. Prefer S1+S2 server-side; it's less code overall and keeps the client thin.

---

## Option-by-option (fact-checked, June 2026)

### Native plugin — Media3/ExoPlayer + AVPlayer/AVKit  ✅ recommended
- **PiP:** Native on **both**. Android Activity PiP (API 26+, `setAutoEnterEnabled` on 12+); iOS `AVPlayerViewController.allowsPictureInPicturePlayback`. (iOS gotcha: PiP must start from a user gesture or App Store rejects.)
- **Background / media session:** Built into the frameworks — Android `MediaSessionService` + foreground service; iOS `AVAudioSession.playback` + `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter`. No third-party glue.
- **HLS/ABR/CMAF:** Both strong and native. ExoPlayer HLS handles fMP4/CMAF + automatic ABR; AVPlayer is Apple's own HLS. (Gaps cluster in DRM — irrelevant; Argosy is non-DRM.)
- **HEVC/4K:** ExoPlayer → MediaCodec (device-dependent; some Android lacks HW HEVC → falls back to server transcode, which is exactly the capability-gate design). iOS VideoToolbox HEVC solid on modern devices.
- **Sidecar WebVTT:** Android easy (`MediaItem.SubtitleConfiguration`). iOS needs S2 (manifest) or a resource-loader.
- **Auth:** Android `setDefaultRequestProperties` for headers; with S1, `?token=` works uniformly on both. Small binary (system frameworks + ExoPlayer).
- **Cost:** Two native codebases we own, tracking Media3 + AVKit changes. This is the real price.

### better_player_plus (v1.3.4) — pragmatic shortcut, spike first
- Maintained fork of the (abandoned) better_player. Lists PiP both platforms, built-in notifications, HLS track selection, full SRT/WebVTT subtitle system with external URLs + styling, HTTP headers. Recent v1.3.2 iOS fMP4/CMAF HLS caching fix shows active upkeep.
- AVPlayer/ExoPlayer-backed → **inherits the same iOS sidecar-WebVTT-in-PiP question**. Its subtitle system is solid on Android; the iOS-in-PiP behaviour is the thing to spike. If it works against an S2 manifest stream, it replaces the native plugin. Risk: single-fork bus-factor.

### media_kit (libmpv) — runner-up / fallback
- **Best-in-class sidecar subtitles** (`SubtitleTrack.uri()`, runtime switch, styling — libmpv renders them itself, so they'd survive in *its* PiP surface) and broadest codec coverage; one engine across mobile + any future desktop/web surface.
- **PiP:** No native PiP in any released version. Exists only as **open, unmerged PR #1410** (iOS 15+/Android 8+, sample-buffer route), last activity 2026-05-30, with known iOS podspec + seek-in-PiP bugs; downstream projects vendor patched copies.
- **Maintenance:** Maintainer declared **"Limited Maintenance"** (Nov 2025). **HLS ABR rendition control is an unanswered open issue** (#1184). Background needs `audio_service` wiring with no confirmed video recipe. libmpv+ffmpeg add tens of MB per ABI.
- **Verdict:** Hold as fallback. If #1410 merges and stabilises before we commit, re-evaluate — it could leapfrog the native plugin.

### Ruled out
- **video_player / chewie:** no PiP, single-track captions only, no media session. chewie is just UI over video_player.
- **better_player (original):** abandoned 2021.
- **fvp (libmdk):** maintainer explicitly **declined PiP** (#113); texture-rendered. Genuinely best HEVC/HDR HW decode, but no PiP kills it here.
- **better_native_video_player:** its own docs admit iOS sidecar subs render in a Flutter overlay **invisible in PiP/fullscreen/AirPlay** — fails the hard requirement. Unverified uploader.
- **flutter_vlc_player / dart_vlc:** texture-based (no native PiP) / abandoned.
- **Precedent:** Fladder (Jellyfin Flutter client) ships media_kit *and* fvp, hit stutter/SW-fallback + HDR issues on weak Android, and **built a native Android Activity player** for full HDR/PiP. Real self-hosted clients reach for native players for PiP/HDR.

---

## Argosy server contract the player must implement (reference)

Extracted from code — see citations at bottom.

- **Auth:** `POST /auth/login` → pick profile → `POST /auth/devices` (returns per-device bearer `token`) → `GET /auth/me` to restore. Bearer header for normal calls; `?token=` query for `/stream`, `/subtitles`, `/beacon` (and, post-S1, transcode HLS).
- **Transcode/HLS:** `POST /api/v1/items/{id}/transcode` body `{ startAt, hevc }` → 202 `{ id, method: remux|transcode, playlistUrl: /api/v1/transcode/{sid}/index.m3u8, ... }`. **CMAF/fMP4** segments (`init_N.mp4` + `stream_N_NNNNN.m4s`), `independent_segments`. Same `startAt`+`hevc` **joins** an existing session (no duplicate encode). `DELETE /api/v1/transcode/{sid}` → 204 to tear down.
- **Capability gate (mirror the web):** `GET /items/{id}/playback` → `{ directPlay, method: direct|remux|transcode, container, videoCodec, audioCodec }`. Direct containers `mp4/m4v/webm/mov`; direct video `h264/avc1/vp8/vp9/av1`; direct audio `aac/mp3/opus/vorbis/flac`. `.mkv` is **never** direct. Web's `supportsHevc()` probes `video/mp4; codecs="hvc1.2.4.L153.B0"` (Main 10 L5.1) → send as `hevc:true` so the server copies 4K HEVC instead of re-encoding to H.264 1080p.
- **Subtitles:** `GET /items/{id}/subtitles` → `[{ id, source: embedded|opensubtitles, language, label, forced, default }]`; fetch `GET /items/{id}/subtitles/{trackId}?token=` → `text/vtt`.
- **Resume/progress:** `GET /items/{id}/progress` → `{ positionSeconds, durationSeconds, watched, updatedAt }`; `PUT /items/{id}/progress` `{ positionSeconds, durationSeconds }` (last-write-wins, auto-watched ≥95%, fans out to Beacon). `POST /items/{id}/watched` `{ watched }`.
- **Beacon SSE:** `GET /api/v1/beacon?token=` → `event: position` with `{ userId, itemId, positionSeconds, durationSeconds, watched, originDeviceId, updatedAt }`. Ignore events where `originDeviceId == this device` (echo); on reconnect, re-fetch `/progress` to reconcile.

---

## Decision points for Arin (before the spike closes)

Under the Android-first scope the decisions shrink to:
1. **Endorse `better_player_plus` as the Android lead**, with the native-ExoPlayer plugin as the escape hatch if the proof's Android PiP/subtitle tests fail? (media_kit dropped — no Android PiP today.)
2. **Confirm the iOS server work stays deferred** to **ARGY-82** (S1 token-on-HLS + S2 manifest subtitles) — i.e. iOS is theory-only for now. *Already filed Backlog/low; this is just a confirm.*

The bus-factor of depending on a single-maintainer fork (`better_player_plus`) is the one ongoing-maintenance call worth a conscious nod — mitigated by it being a thin wrapper over ExoPlayer, so the escape hatch shares the same engine knowledge.

---

## Validation checklist — the throwaway proof (hands-on session)

Run against the live dev server on **:8097**, on a **real Android device** (PiP + HW HEVC can't be validated on simulators/headless). Use `better_player_plus`; if a checked item fails, fall to the native-ExoPlayer escape hatch.

- [ ] Install Flutter SDK; scaffold a throwaway app under `mobile/`.
- [ ] Auth: `login` → `devices` → store token → `me`.
- [ ] **Direct play:** `/items/{id}/stream?token=` an H.264/AAC mp4; seek + resume.
- [ ] **Transcode HLS:** `POST /transcode {hevc:true}` → play `playlistUrl` with the Bearer header (Android sets headers fine — no S1 needed). Watch an ABR rendition switch happen.
- [ ] **HEVC/4K:** play a true-4K HEVC source with `hevc:true`; confirm HW decode (no SW fallback) on the device; confirm fallback to H.264 transcode when the gate says so.
- [ ] **Subtitles:** select a sidecar WebVTT track; confirm it renders + switches at runtime (ExoPlayer handles sidecar VTT natively).
- [ ] **PiP:** enter PiP from a user gesture on Android; playback continues; controls work. *(This is the make-or-break test for `better_player_plus` vs the native escape hatch.)*
- [ ] **Background / lock screen:** audio continues; now-playing controls (play/pause/seek) appear and work.
- [ ] **Resume + Beacon:** `PUT /progress` heartbeat; kill app, reopen, resume from `/progress`; change position on another device and confirm the SSE `position` event updates this client (and that self-origin echoes are ignored).
- [ ] Record APK size delta for the chosen engine.

**iOS (deferred — do NOT run now):** when iOS is targeted, land **ARGY-82** (S1 token-on-HLS + S2 manifest subtitles) first, then validate AVPlayer HLS auth, subtitle-track-in-PiP, and PiP-from-gesture on a real iPhone (needs a Mac + Apple Developer Program).

Outcome of this session → final recommendation, then the spike closes and feeds ARGY-45 (scaffold) + ARGY-79 (player screen).

---

## Citations

Server (this repo): `internal/api/argosy.gen.go` (DTOs); `internal/library/playback.go:19-166` (capability gate); `internal/library/transcode.go:89-258` + `internal/transcode/ffmpeg.go:140-250` (CMAF/fMP4 HLS, `-hls_segment_type fmp4`); `internal/library/subtitle.go:65-121`; `internal/library/progress.go:76-289`; `internal/library/stream.go:85-144`; `internal/library/beacon.go` + `internal/beacon/beacon.go:24-32`; `web/src/lib/playback.ts:36-118` (`supportsHevc()`); `proto/openapi/argosy.yaml`.

Flutter (external, fact-checked June 2026): flutter/flutter#60048 (iOS PiP needs custom player); media-kit/media-kit PR #1410 (unmerged iOS PiP), issue #1337 (Limited Maintenance), #1184 (HLS ABR); Apple `AVPictureInPictureController` / `AVPlayerViewController.allowsPictureInPicturePlayback` docs + Developer Forums 99598/26866 (AVPlayer rejects sidecar WebVTT); developer.android.com PiP + Media3 `MediaSessionService` docs; pub.dev `better_player_plus` v1.3.4, `fvp` v0.37.2 (#113 PiP declined), `better_native_video_player` v1.2.0 (overlay-only iOS subs).
