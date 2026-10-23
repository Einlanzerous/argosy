# Client parity: which fixes cover which client

Argosy has four places a fix can land: **web** (`web/src`, hls.js), **phone**
and **TV** (`mobile/argosy/lib`, better_player / ExoPlayer; phone and TV share
`PlaybackController`, so a controller fix covers both but UI-layer fixes do
not), and the **server** (`internal/`). A bug fixed on one client has repeatedly
been rediscovered on another months later (ARGY-103 → ARGY-228, the `el.duration`
fix → ARGY-230, ARGY-107 → ARGY-239). This page records, per fix, which side it
needs, and where a side is missing.

Produced by the ARGY-233 audit (2026-10-23) at `main` = `2c100e7`. Read from code,
not run; "unverified" marks what only reading could not settle.

## Classes

- **shared**: the behaviour is client-visible on every client. Fixing one side is
  a half-fix; the PR must say what happened to the others.
- **web-only**: hls.js or browser specific (codec strings, `useMediaCapabilities`,
  secure-context APIs, SPA caching). Nothing to port.
- **mobile-only**: better_player / ExoPlayer / Android specific.
- **server**: fixed once, covers every client.

## Playback lifecycle

| Ticket | Fix | Class | Web | Phone | TV | Gap |
|---|---|---|---|---|---|---|
| ARGY-94 | Progress PUT touches the session; idle TTL 5 min | server | ok | ok | ok | none |
| ARGY-103 | Start at 0, not the live edge | shared | ok (`startPosition: 0`) | server tag only | server tag only | ARGY-258 (unproven on phone) |
| ARGY-228 | `#EXT-X-START` in served media playlists | server | ok | ok | ok (observed on TV) | ARGY-258 |
| ARGY-106 | Playlists `no-store`, no 304 | server | n/a | n/a | n/a | none |
| ARGY-107 | Recover a reaped session; keepalive while paused | shared | ok | ok (ARGY-239) | ok | ARGY-259 (web keepalive uncapped) |
| ARGY-220/223 | Bounded recovery retries, re-armed by real progress | shared | ok | ok | ok | none |
| ARGY-230 | Pin duration so a seek can't finish the stream | mobile-only | ok by construction | ok | ok | none |
| ARGY-108 | Back goes to the title page | shared | ok | ok | ok | none |
| ARGY-84 | `-noaccurate_seek` on resumed remux | server | n/a | n/a | n/a | none |
| ARGY-190 | Release the transcode when the host dies | mobile-only | n/a | ok | ok | none |

## Transport, advance, capabilities

| Ticket | Fix | Class | Web | Phone | TV | Gap |
|---|---|---|---|---|---|---|
| ARGY-90/101 | Credits-triggered Up Next | shared | ok | ok | ok | ARGY-259 (two copies of the 40 s lead) |
| ARGY-207 | Up Next real countdown | shared | ok | ok | ok | none |
| ARGY-125 | Remaining-time scrubber | shared | ok | ok | ok | none |
| ARGY-134 | Episode title in header | shared | ok | ok | ok | none |
| ARGY-105 | Forgiving seek bar, drag to scrub | web-only | ok | stock slider | D-pad only | by design |
| ARGY-133 | Deeper client buffering | per client | ok | ok | ok | none |
| ARGY-177 | ABR opens at the top rung | web-only | ok | n/a (ExoPlayer) | n/a | unverified on phone |
| ARGY-150 | 10-bit HEVC/H.264 transcodes to 8-bit | server | n/a | inherits | inherits | none |
| ARGY-178 | Keep 10-bit HEVC when the client decodes in hardware | shared signal | sends `hevcHardware` | **never sent** | **never sent** | ARGY-252 |
| ARGY-87 / ARGY-50 | Lock-screen controls, PiP, wakelock | mobile-only | n/a | ok | not checked | none |

Seek and skip steps are ±10 s on all three clients.

## Tracks and subtitles

| Ticket | Fix | Class | Web | Phone | TV | Gap |
|---|---|---|---|---|---|---|
| ARGY-60 | Caption styling and position | shared (prefs) | in-player | settings only | settings only | UX difference, not a bug |
| ARGY-208 | Prefs saves don't wipe other fields | mobile-only | ok (spread) | ok | ok | none |
| ARGY-127/128/129 | Multi-audio renditions, picker, auto-select | shared | ok | ok | ok | ARGY-254 (active-track tick) |
| ARGY-152 | Picker stays inside the viewport | web-only | ok | bottom sheet, unverified with 20+ tracks | same | unverified |
| ARGY-153 | Embedded tracks before OpenSubtitles | server | n/a | n/a | n/a | none |
| ARGY-154 | Preferred-language fold | shared | ok | ok | ok | none |
| ARGY-155 | VTT cache GC | server | n/a | n/a | n/a | none |
| ARGY-59 | Burn-in of image subtitles | shared | ok | **tracks filtered out** | **tracks filtered out** | ARGY-253 |
| ARGY-248 | Audio on its own button | shared | ok (existing) | ok | ok | none |
| (none) | Default audio when no saved pref | shared | file default | file default | file default | ARGY-255 (`ARGOSY_PREFERRED_LANGUAGES` never picks the default) |

## Browse and account

| Ticket | Fix | Class | Web | Phone | TV | Gap |
|---|---|---|---|---|---|---|
| ARGY-117 | Series opens on the in-progress season | shared | ok | ok | ok | none |
| ARGY-176/182/97 | Episode identity, abandoned samples, dedup | shared + server | ok | ok | ok | none |
| ARGY-237 | Error, not an empty hold, on request failure | shared | ok | Home ok, **Library swallows errors** | same | ARGY-251 |
| ARGY-109/122 | Mark watched/unwatched | shared | ok | ok | badge only, **no toggle** | ARGY-257 |
| ARGY-118 | Per-episode ratings | shared | ok | **not rendered** | **not rendered** | ARGY-256 |
| ARGY-113 | Cast and credits | shared | ok | ok | ok | none |
| ARGY-160 | Change-password UI | web-only (API shared) | ok | none | none | ARGY-259 (may be intended) |
| ARGY-247 | Wrong-password wording | mobile-only | blanket message | ok | ok | ARGY-259 |
| ARGY-192 | HTTPS probing for typed addresses | mobile-only | n/a | ok | ok | none |
| ARGY-123 | Code pairing | shared | ok (approve side) | ok | ok | none |
| ARGY-121 | No secure-context-only APIs | web-only | ok | n/a | n/a | none |
| ARGY-249 | App version in Settings | per client | **missing** | ok | ok | ARGY-259 |
| ARGY-229/231 | Stow | mobile-only | n/a | ok | absent | none |
| ARGY-184/173 | TV focus | TV-only | n/a | n/a | Library and Search lack `TvLandingFocus` | ARGY-259 |

## Rule for new fixes

A PR that touches shared-semantics behaviour states, in its body, one line per
side: **web / phone / TV / server: covered, n/a, or ticket**. "n/a" needs a
reason (for example "hls.js only"). A fix that is shared but lands on one side
files the ticket for the other in the same PR, linked to the originating ticket.
Update this table in the same PR.

Things that are web-only by nature and need no port: hls.js codec-string
handling and `useMediaCapabilities`, secure-context API avoidance, SPA shell
caching and stale-chunk handling.
