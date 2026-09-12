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

Covers:

- [ ] web — `PlayerView.vue`
- [ ] mobile — `playback_controller.dart`
- [ ] TV — `tv_player_screen.dart`

Why the unchecked ones are unaffected:

<!-- One line. "One-sided by nature" is a real answer when it is true: hls.js
     codec strings and useMediaCapabilities, ExoPlayer/better_player quirks,
     secure-context browser APIs. -->

If all three are ticked because this is a server-side fix — the client
behaviour it replaces:

<!-- Name it; three ticks say a fix reaches every player, they do not show it.
     Then check whether the client still carries its own override: web's
     startPosition: 0 is still in PlayerView.vue, right next to the EXT-X-START
     pin that replaced it everywhere else. Delete this prompt if the boxes
     above are not all ticked. -->

## Verification

<!-- What you actually ran or watched. On-device is worth naming: which device,
     which title, what you saw. CI covers the rest. -->
