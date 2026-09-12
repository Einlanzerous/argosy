<!-- Subject: conventional commit with the ticket key, e.g.
     fix(player): pin the session duration so seeks don't finish a
     transcode (ARGY-230). The reviewer resolves the ticket from the
     title first, the branch second. -->

## What

<!-- A sentence or two: what changes, and what it fixes. -->

## Player parity

<!-- REQUIRED when this PR touches web/src/views/PlayerView.vue,
     mobile/argosy/lib/features/player/, internal/transcode/ or
     internal/library/transcode.go AND alters playback semantics — resume and
     seek, playlist start / duration / ENDLIST, auto-advance and credits timing,
     buffering, session keepalive and recovery, subtitle or audio preference.
     Delete the whole section if the PR touches none of that. See REVIEW.md. -->

- [ ] web — `PlayerView.vue`
- [ ] mobile — `playback_controller.dart`
- [ ] TV — `tv_player_screen.dart`

Why the unchecked ones are unaffected:

<!-- One line. "One-sided by nature" is a real answer when it is true: hls.js
     codec strings and useMediaCapabilities, ExoPlayer/better_player quirks,
     secure-context browser APIs. A server-side fix ticks all three only if you
     name the client behaviour it replaces — and check whether the client still
     carries its own override (web's startPosition: 0 outlived the EXT-X-START
     pin that replaced it everywhere else). -->

## Verification

<!-- What you actually ran or watched. On-device is worth naming: which device,
     which title, what you saw. CI covers the rest. -->
