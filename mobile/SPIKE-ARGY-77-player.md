# ARGY-77 — Flutter player spike: decision doc

**Status:** Recommendation drafted (desk research complete). **Pending:** on-device PiP validation + Arin's build-vs-buy/server-change sign-off before the spike can close.
**Date:** 2026-06-21

This doc is the *recommendation* half of ARGY-77. The *throwaway proof* half (a `mobile/` Flutter app exercising the live `:8097` server) still needs a hands-on session with the Flutter SDK and **real Android + iOS devices** — PiP and HW HEVC cannot be validated headless. The "Validation checklist" at the end is the exact script for that session.

---

## TL;DR recommendation

1. **Player layer:** Build a **thin native plugin** over **Media3/ExoPlayer (Android) + AVPlayer/AVKit (iOS)**. It is the only approach that delivers *native PiP on iOS with subtitles that survive inside the PiP window* — Argosy's hard requirement.
2. **Pragmatic shortcut to spike first:** **`better_player_plus`** (v1.3.4, actively maintained, AVPlayer/ExoPlayer-backed) claims the whole matrix. If its iOS subtitle behaviour holds up *inside PiP* against a manifest-delivered track, it saves us the native plugin. It probably won't (it's AVPlayer-backed and shares the constraint) — but it's a one-day spike that could save weeks, so try it before hand-rolling.
3. **Two server-side changes make the mobile player dramatically simpler** (details below). Both mirror patterns the server already implements. This contradicts the Phase 6 memory's "no server work expected for the MVP" — the spike found otherwise.
4. **Runner-up:** **media_kit** (libmpv). Single most capable engine *if* its unmerged iOS-PiP PR (#1410) ever ships and stabilises. Today it's blocked on that PR + a self-declared "Limited Maintenance" notice + an open question on HLS ABR control. Hold as fallback.

---

## Why this is hard: two requirements in direct tension

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

1. **Approve the two server changes** S1 (token query on transcode HLS — strongly recommended, near-zero cost) and S2 (manifest subtitle injection — recommended; fallback is iOS resource-loader glue)?
2. **Build-vs-buy the player:** authorise the native plugin, or require a `better_player_plus` spike first to try to avoid it?
3. **Accept the cost:** native plugin = two codebases we maintain forever vs. better_player_plus single-fork dependency vs. waiting on media_kit #1410.

These are architectural + ongoing-maintenance commitments, so they're Arin's call, not mine — hence the spike stays open pending sign-off.

---

## Validation checklist — the throwaway proof (hands-on session)

Run against the live dev server on **:8097**, on a **real Android device and a real iOS device** (PiP + HW HEVC can't be validated on simulators/headless):

- [ ] Install Flutter SDK; scaffold a throwaway app under `mobile/`.
- [ ] Auth: `login` → `devices` → store token → `me`.
- [ ] **Direct play:** `/items/{id}/stream?token=` an H.264/AAC mp4; seek + resume.
- [ ] **Transcode HLS:** `POST /transcode {hevc:true}` → play `playlistUrl`. **Confirms S1** is needed/works (does the player auth to the m3u8 + `.m4s`?). Watch an ABR rendition switch happen.
- [ ] **HEVC/4K:** play a true-4K HEVC source with `hevc:true`; confirm HW decode (no SW fallback) on each device; confirm fallback to H.264 transcode when the gate says so.
- [ ] **Subtitles:** select a WebVTT track; **confirm it renders — and stays visible inside the PiP window — on iOS** (this is the make-or-break test for S2 vs sidecar).
- [ ] **PiP:** enter PiP from a user gesture on Android **and** iOS; playback continues; controls work.
- [ ] **Background / lock screen:** audio continues; now-playing controls (play/pause/seek) appear and work.
- [ ] **Resume + Beacon:** `PUT /progress` heartbeat; kill app, reopen, resume from `/progress`; change position on another device and confirm the SSE `position` event updates this client (and that self-origin echoes are ignored).
- [ ] Record APK/IPA size delta for the chosen engine.

Outcome of this session → final recommendation, then the spike closes and feeds ARGY-45 (scaffold) + ARGY-79 (player screen).

---

## Citations

Server (this repo): `internal/api/argosy.gen.go` (DTOs); `internal/library/playback.go:19-166` (capability gate); `internal/library/transcode.go:89-258` + `internal/transcode/ffmpeg.go:140-250` (CMAF/fMP4 HLS, `-hls_segment_type fmp4`); `internal/library/subtitle.go:65-121`; `internal/library/progress.go:76-289`; `internal/library/stream.go:85-144`; `internal/library/beacon.go` + `internal/beacon/beacon.go:24-32`; `web/src/lib/playback.ts:36-118` (`supportsHevc()`); `proto/openapi/argosy.yaml`.

Flutter (external, fact-checked June 2026): flutter/flutter#60048 (iOS PiP needs custom player); media-kit/media-kit PR #1410 (unmerged iOS PiP), issue #1337 (Limited Maintenance), #1184 (HLS ABR); Apple `AVPictureInPictureController` / `AVPlayerViewController.allowsPictureInPicturePlayback` docs + Developer Forums 99598/26866 (AVPlayer rejects sidecar WebVTT); developer.android.com PiP + Media3 `MediaSessionService` docs; pub.dev `better_player_plus` v1.3.4, `fvp` v0.37.2 (#113 PiP declined), `better_native_video_player` v1.2.0 (overlay-only iOS subs).
