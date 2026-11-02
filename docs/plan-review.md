# Reviewing a plan

What Switchyard's adversarial plan pass verifies an **ARGY** plan against.
`REVIEW.md` is the judgement for a diff; this file is the judgement for a plan,
before any diff exists. The procedure (workflow, verdict file, check row) lives
in Switchyard (`.github/workflows/plan-review.yml`, `docs/plan-as-pr.md` there).
`CLAUDE.md` outranks this file, as it does `REVIEW.md`. Counterparts:
`chronicle/REVIEW.md` § Reviewing a plan (CHRN-102) and `catenary/docs/plan-review.md`
(CANT-150). Drawn from the hand review of ARGY-179 rev 1, so the playback-path
checks are the errors an ARGY plan actually makes.

## Who reads this and what they hold

You are the pass. On disk: `plan.json` (sections with `anchor`, criteria with
`method`, `rulings[]` with `options[]`, `recommended_position`,
`chosen_option_id`, `required`, work breakdown, prior `reviews` and `threads`),
`plan-context.json` (`review_mode`, `live_required_ruling`), `ticket.json`, and a
read-only checkout of this repository's default branch. Tools: Bash, Read, Grep,
Glob. You have **no Switchyard access**; other tickets' states and other
repositories are not on disk and not yours to fetch. You write one verdict file:
`blocking[]` and `advisory[]` (each `{section_anchor, quoted_text, body_md}`) and
`summary_md`. `section_anchor` must name a section in *this* revision or the
finding is dropped.

## Checks

Each is decidable from the checkout plus the plan JSON. A claim about another
repository (construct-server, purser, a Flutter plugin's source, Media3,
ExoPlayer internals) is **unverified**, never *false*: say what would verify it
and do not bounce on it.

### 1. Citations exist

Open every cited path, symbol, line and count (`Glob`, `Grep`, `Read`). A wrong
citation the recommended path rests on is blocking; a stale line number beside a
correct argument is advisory. A premise the tree already contradicts is
blocking: read the function before accepting a problem statement. A state the
plan calls open or unbuilt may have merged since; look for the artefact on the
tree, not `git log` (the pass runs on a shallow checkout). Generated paths in
`.github/review-ignore` (`internal/api/argosy.gen.go`, `web/src/api/schema.ts`,
`mobile/argosy/packages/argosy_api/`, `graphify-out/`) are not evidence for what
a hand-written file does.

### 2. `CLAUDE.md`'s invariants are blocking checks

A plan whose recommended path violates one is bounced, not advised. Each names
what decides it:

- **Audit writes outlive the request**: a new audited action detaches with
  `context.WithoutCancel`, as `internal/auth/audit.go` does.
- **Wrong password is 403, never 401**: `ErrWrongPassword` maps to 403 in
  `internal/auth/handlers.go`; 401 signs the device out.
- **Sign-in costs the same whether the email exists**: every no-hash path goes
  through `comparePassword` and `dummyPasswordHash` (`internal/auth/auth.go`).
- **Reset revokes devices, change does not**: `ResetAccountPassword` in
  `internal/auth/accounts.go`.
- **`DeleteAccount` refuses owners of library rows**: `ErrAccountHasLibraries`.
- **Instance ownership** (ARGY-167): `internal/auth/owner.go`; the plan says
  whether it keys on instance or on per-library ownership.
- **No secure-context browser APIs** (`crypto.randomUUID`, clipboard, service
  workers): the web UI is served over plain HTTP.
- **Playlists and the SPA shell are uncacheable**: playlists `no-store` in
  `internal/library/transcode.go`, the shell in `internal/server/spa.go`; no
  `http.ServeFile` for content that changes within a second.
- **Transcode sessions are reaped and the player survives it**: a new playback
  path says how it recovers a vanished session and how it keeps one alive while
  paused (ARGY-107).
- **One ffmpeg version**: `.ffmpeg-version`, checked by
  `scripts/check-ffmpeg-pin.sh` (`make check-ffmpeg`). A plan that relies on
  ffmpeg output shape or flags names the pinned version, not "ffmpeg".
- **Hardware encode is VAAPI and `Probe` means a real encode succeeded**:
  `Probe` in `internal/transcode/capabilities.go`. A plan that assumes QSV, or
  that availability is "encoder built plus `/dev/dri`", is blocking.

### 3. The playback path's shape is stated, not assumed

ARGY-179 rev 1 got three things wrong here. A plan that adds or removes a rung,
variant or codec, or changes what a client asks for, must state all of:

1. **Which manifest shape the output has.** `buildArgs` (`internal/transcode/ffmpeg.go`)
   picks between `buildRemuxArgs`, `buildSingleTranscodeArgs` and `buildLadderArgs`.
   A single-variant output ends in `singleOutputTail`, which writes a **media
   playlist** with no master and no `CODECS`; a master (`hlsMasterTail`) is
   written only for a ladder, `multiAudio`, or `needsCodecDeclaration`. A plan
   that says a single-rung H.264 transcode yields a master, or that a client
   gets variant or `BANDWIDTH` information from a lone rung, is checked against
   those functions and is blocking if wrong.
2. **Which `sessionID` key fields move** (`sessionID` in
   `internal/transcode/transcode.go`). Hints must enter the key as the
   *effective* rung set (`shapedRungs`), not raw values, or two clients that
   resolve to the same encode stop sharing one. An unhinted or old client's key
   must stay byte-identical so in-flight sessions rejoin across a deploy
   (ARGY-239); `TestSessionIDGoldenUnhinted` and `TestSessionIDKeysOnEffectiveRungs`
   in `internal/transcode/session_identity_test.go` are the guards, and a plan
   that changes the key names how they change. Raw hint values in the key are blocking.
3. **Whether remux and transcode diverge.** `PlannedRungs` returns nil for a
   remux, a copy has one variant by construction, and ARGY-235 owns giving a
   remux a ladder. A plan that applies a hint or rung to both says so.

A precedent cited for any of this is read, not trusted. `packageRung`
(`internal/transcode/package.go`) is the *offline package* rung: one H.264 MP4,
no HLS, no ladder. It is not a precedent for streaming-ladder behaviour, and a
plan resting on it for one is blocking. The streaming ladder is
`rungsForCodec` / `boundedRungs`.

### 4. The API contract fans out

A change under `proto/openapi/` names the consumers that regenerate: Go
(`internal/api/argosy.gen.go`), TS (`web/src/api/schema.ts`) and Dart
(`mobile/argosy/packages/argosy_api/`), via `make generate` (`gen:dart` needs a
JDK, in `~/dev-tools/jdk` on the dev box), and says the `openapi-drift` job in
`ci.yml` stays green. A hand edit of a generated file is blocking.

### 5. Migrations

`internal/db/migrations/` holds goose files named `NNNNN_name.sql`, embedded and
applied in order at startup. The plan's number is one past
`ls internal/db/migrations | tail -1`, not its own say-so. A change is additive
and safe against pre-ARGY-167 data the ownership backfill never moved
(`00023`). `internal/db/seed.sql` is dev-only and never a migration's substitute.

### 6. Player parity

`docs/player-parity.md` is the table; `REVIEW.md` § Player parity is the rule.
A plan that changes playback semantics on one of web
(`web/src/views/PlayerView.vue`), phone (`mobile/argosy/lib/features/player/playback_controller.dart`)
or TV (`.../player/tv/tv_player_screen.dart`) says what the other two do or why
they differ, and which fix class it is (shared, web-only, mobile-only, server).
A server-side fix claims all three only by naming the client behaviour it
replaces. Check the claim against the sibling file; "web only" over a threshold
duplicated in the Dart is blocking. A plan that adds a row owes an update to the table.

### 7. Mobile and platform claims

Checked against the Flutter tree, not memory: `mobile/argosy/pubspec.yaml` pins
(`better_player_plus`), `minSdk`/`targetSdk` (both `flutter.*` defaults in
`mobile/argosy/android/app/build.gradle.kts`, so the number comes from the
pinned Flutter SDK), `IPHONEOS_DEPLOYMENT_TARGET` in
`mobile/argosy/ios/Runner.xcodeproj/project.pbxproj` (**13.0**), and the real
platform-channel surface (`mobile/argosy/lib/platform/device_capabilities.dart`,
`MainActivity.kt`). "Every iOS 15 device" against a 13.0 target is a false
premise. The Media3/ExoPlayer version a plugin ships is unverified unless its
source is on disk.

### 8. Numbers from elsewhere carry their constraints

A bitrate, TTL, rung height, buffer size or cap copied from hls.js, Media3,
ffmpeg or another service says which version it holds for. Check the arithmetic
against this repository's constants (`internal/transcode/`), and the ffmpeg
claim against `.ffmpeg-version`. Blocking when the recommended path's
arithmetic fails.

### 9. Criteria have a method this ticket can run

`method` is free text and may be null; null, or a method nobody can run (a
manual check with no actor), is blocking. Specifically:

- A Go test criterion: `make test` needs `ARGOSY_TEST_DATABASE_URL` (DB tests
  skip when unset, via `internal/testdb`) and ffmpeg at the `.ffmpeg-version`
  package; tests guarded by `testing.Short()` (for example
  `internal/transcode/ffmpeg_manifest_test.go`) skip under `-short`. A criterion
  whose test would silently skip is not discharged.
- An on-device criterion names the device (Pixel, Google TV dongle, Sony TV) and
  who acts and when.
- `graphify-out/` is owned by `.github/workflows/graphify.yml` and is never a
  deliverable of a branch.
- Every recommended option has a criterion that fails if it is not implemented.
  A criterion needing code the ticket says it will not ship names the ticket
  that does. Criteria are quoted by opening words, not number.

## Your standing

Advisory on a passing check. Blocking only for a hole a person would bounce the
revision for: a false premise or contradicted citation on the recommended path,
an invariant violated, a playback-shape or session-key statement missing where
the path is touched, a criterion that cannot be run or is not this ticket's, or
an unmarked either/or. Style, ordering and everything about a non-recommended
option is advisory.

Mirror SWY-441 on rulings. Scrutiny goes to the option at `recommended_position`
and to the criteria and breakdown written for it; a non-recommended option gets
an **honesty check only** (is its description false, or written to flatter the
recommendation?). A genuine either/or argued in prose with no ruling attached is
blocking. You never pick a ruling, never write that an option "is rejected",
never supersede, and never approve a plan carrying a human-only ruling. Where
`live_required_ruling` is false you are the last gate before an agent approval;
weigh a clean pass accordingly and say so in `summary_md`.

## Ready for a human

All of, as the loop (SWY-445) reads them:

- no blocking finding on the recommended path;
- every genuine either/or has a ruling, with one `recommended_position` its own
  option text does not contradict;
- every criterion has a non-null `method` this ticket can run, or names the
  ticket that does;
- every cited path and symbol exists, and every other-repository claim is marked
  unverified rather than false;
- if the playback path is touched, the manifest-shape, `sessionID` key and
  remux-versus-transcode statements of check 3 are present, and the parity
  statement of check 6.

Reaching it means **a person is now owed the rulings**: the plan is ready to be
read, not approved. Not reaching it means one `changes_requested` carrying the
blocking findings.
