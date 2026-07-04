# Changelog

## [0.10.1](https://github.com/Einlanzerous/argosy/compare/v0.10.0...v0.10.1) (2026-07-04)


### Bug Fixes

* **ci:** run check-apple from workspace root (no checkout) (ARGY-88) ([#129](https://github.com/Einlanzerous/argosy/issues/129)) ([5d58847](https://github.com/Einlanzerous/argosy/commit/5d58847739078c74f2915f90a62b57ba1385d90b))
* **mobile:** TV pairing replace-on-first-keystroke + name attempted URL (ARGY-124) ([#131](https://github.com/Einlanzerous/argosy/issues/131)) ([dfef6b0](https://github.com/Einlanzerous/argosy/commit/dfef6b00866833060548d60e07114d91a8d1fedd))

## [0.10.0](https://github.com/Einlanzerous/argosy/compare/v0.9.0...v0.10.0) (2026-07-04)


### Features

* **library:** drop the labels feature (ARGY-110) ([#126](https://github.com/Einlanzerous/argosy/issues/126)) ([490b629](https://github.com/Einlanzerous/argosy/commit/490b6294fde0d427fd8f8daf84b9e8065e9d6845))


### Bug Fixes

* **ci:** correct release-please tag output + gate iOS stub (ARGY-88) ([#128](https://github.com/Einlanzerous/argosy/issues/128)) ([1ae67a7](https://github.com/Einlanzerous/argosy/commit/1ae67a7e674bda439b161d64922b0754185c62ba))

## [0.9.0](https://github.com/Einlanzerous/argosy/compare/v0.8.1...v0.9.0) (2026-07-02)


### Features

* **auth:** in-place device profile switch — re-bind endpoint + Flutter picker (ARGY-85) ([#112](https://github.com/Einlanzerous/argosy/issues/112)) ([637982d](https://github.com/Einlanzerous/argosy/commit/637982d6b4e617616ba5b6fd27b38adfc1e3c6cc))
* **detail:** enlarge series & film hero artwork ~40% (ARGY-116) ([#118](https://github.com/Einlanzerous/argosy/issues/118)) ([bc2183b](https://github.com/Einlanzerous/argosy/commit/bc2183b03211b7d42f3e675a306cfc1cf1a0bd74))
* **detail:** per-episode TMDB ratings on series detail (ARGY-118) ([#125](https://github.com/Einlanzerous/argosy/issues/125)) ([f96400b](https://github.com/Einlanzerous/argosy/commit/f96400b4bec32bf13398baae8bd91701fbccf8a6))
* **detail:** scale mobile detail hero with the viewport (ARGY-116) ([#119](https://github.com/Einlanzerous/argosy/issues/119)) ([048a3d6](https://github.com/Einlanzerous/argosy/commit/048a3d6ebebffd4c706430866c8de4f71d15849f))
* **detail:** surface cast/credits on movie + series detail views (ARGY-113) ([#120](https://github.com/Einlanzerous/argosy/issues/120)) ([174a7cb](https://github.com/Einlanzerous/argosy/commit/174a7cba0aea139dec63ebd2a7f23dfde52a2108))
* **home:** last-played device pill on resume items (ARGY-98) ([#108](https://github.com/Einlanzerous/argosy/issues/108)) ([50b9d23](https://github.com/Einlanzerous/argosy/commit/50b9d2314e02a475048db6bba1503a43a2e25a79))
* **library:** mark episodes/items watched or unwatched (ARGY-109) ([#124](https://github.com/Einlanzerous/argosy/issues/124)) ([b6892da](https://github.com/Einlanzerous/argosy/commit/b6892da04faebd3ddcaf53e9d57c60f534f47b44))
* **player:** caption position presets (Bottom/Raised/Higher) (ARGY-60) ([#110](https://github.com/Einlanzerous/argosy/issues/110)) ([51a4949](https://github.com/Einlanzerous/argosy/commit/51a4949071156570a37095667ff1a3742f6f6319))
* **player:** forgiving seek-bar hit area + drag-to-scrub (ARGY-105) ([#123](https://github.com/Einlanzerous/argosy/issues/123)) ([3e51a5c](https://github.com/Einlanzerous/argosy/commit/3e51a5cf81edc268b33b5de115795611e661ca70))
* **profiles:** account profile management — CRUD + web admin screen (ARGY-65) ([#111](https://github.com/Einlanzerous/argosy/issues/111)) ([b8f02a0](https://github.com/Einlanzerous/argosy/commit/b8f02a018f64f2c49360c8436e013394e9fe8676))
* **search:** people/cast search via TMDB credits ingest + backfill (ARGY-67) ([#109](https://github.com/Einlanzerous/argosy/issues/109)) ([21b7363](https://github.com/Einlanzerous/argosy/commit/21b736327b9e084a276c35aba3f4f3a2aa0a92a6))
* **tv:** Android TV foundation + phone code-pairing (ARGY-51, ARGY-112) ([#105](https://github.com/Einlanzerous/argosy/issues/105)) ([35aaa0c](https://github.com/Einlanzerous/argosy/commit/35aaa0c88d27430ec33f3fbc5cfa2fbc64d40a88))
* **tv:** TVHome/detail/player core loop with D-pad focus (ARGY-51) ([#106](https://github.com/Einlanzerous/argosy/issues/106)) ([87a41e2](https://github.com/Einlanzerous/argosy/commit/87a41e2041fdf726a244679df63b3667da83d227))
* **tv:** TVLibrary/Search/Settings — PR3 completes the Android TV shell (ARGY-51) ([#107](https://github.com/Einlanzerous/argosy/issues/107)) ([cad21f5](https://github.com/Einlanzerous/argosy/commit/cad21f5c963465bd8415e4b437b06fe2ca487263))


### Bug Fixes

* **android:** disable R8 minify for release — fixes launch crash (ARGY-114) ([#113](https://github.com/Einlanzerous/argosy/issues/113)) ([ed215a5](https://github.com/Einlanzerous/argosy/commit/ed215a5491552c0d3ef3ff87d2eadaab7f42d6e2))
* **detail:** make the film hero ~20% taller than the series hero (web) ([#122](https://github.com/Einlanzerous/argosy/issues/122)) ([156705d](https://github.com/Einlanzerous/argosy/commit/156705d8c77ab2cca4bb90d83c8c91178befdf70))
* **detail:** open series on the in-progress season, not always Season 1 (ARGY-117) ([#117](https://github.com/Einlanzerous/argosy/issues/117)) ([c93a4fb](https://github.com/Einlanzerous/argosy/commit/c93a4fb3fc975d0e4ed620f3983068608b8eb582))
* **fleet:** dedup device registrations on re-pair via stable install id (ARGY-99) ([#102](https://github.com/Einlanzerous/argosy/issues/102)) ([5340cb1](https://github.com/Einlanzerous/argosy/commit/5340cb143804e1619edf3d0def675b25808a86cd))
* **mobile:** keep sign-in fields above the keyboard on pairing screen ([#116](https://github.com/Einlanzerous/argosy/issues/116)) ([02932ee](https://github.com/Einlanzerous/argosy/commit/02932ee31afb1b638e2786d555e1835bd4b46fa5))
* **web:** mint opaque install id via getRandomValues, not crypto.randomUUID (ARGY-121) ([#121](https://github.com/Einlanzerous/argosy/issues/121)) ([a521bd8](https://github.com/Einlanzerous/argosy/commit/a521bd826822cbfda90f8924c8b806caf69e567f))

## [0.8.1](https://github.com/Einlanzerous/argosy/compare/v0.8.0...v0.8.1) (2026-06-26)


### Bug Fixes

* **player:** Back to details goes to the title page, not a previous episode (ARGY-108) ([#101](https://github.com/Einlanzerous/argosy/issues/101)) ([4613ad2](https://github.com/Einlanzerous/argosy/commit/4613ad2b6e6fad22b436a841ef7974c5580dd816))
* **player:** recover from reaped transcode session; keepalive while paused (ARGY-107) ([#99](https://github.com/Einlanzerous/argosy/issues/99)) ([0da36f9](https://github.com/Einlanzerous/argosy/commit/0da36f92d4f62106e57443fca06f7bdd5ba3d2da))

## [0.8.0](https://github.com/Einlanzerous/argosy/compare/v0.7.0...v0.8.0) (2026-06-25)


### Features

* **player:** credits-triggered auto-advance + Play Next (web + mobile) (ARGY-90/101) ([#93](https://github.com/Einlanzerous/argosy/issues/93)) ([b5c58d7](https://github.com/Einlanzerous/argosy/commit/b5c58d7901b0096023c8acbd99ee2144aed0bd5e))


### Bug Fixes

* **home:** don't repeat the hero item in the Continue Watching rail (ARGY-97) ([#96](https://github.com/Einlanzerous/argosy/issues/96)) ([f0286c4](https://github.com/Einlanzerous/argosy/commit/f0286c4c8ed2432f709c2894d251be4a56115539))
* **library:** collapse Continue Watching to one entry per series (ARGY-97) ([#95](https://github.com/Einlanzerous/argosy/issues/95)) ([6471f61](https://github.com/Einlanzerous/argosy/commit/6471f611e14f74c4b3123f201320c509a8adb7c9))
* **player:** start fresh playback at position 0, not the live edge (ARGY-103) ([#97](https://github.com/Einlanzerous/argosy/issues/97)) ([21df274](https://github.com/Einlanzerous/argosy/commit/21df274517d03fc89ab9ea04ebc4f529ce0c5496))
* **transcode:** serve HLS playlists uncacheable to prevent stale-304 wedge (ARGY-106) ([#98](https://github.com/Einlanzerous/argosy/issues/98)) ([0810cae](https://github.com/Einlanzerous/argosy/commit/0810cae51505a77fb80b3906876b6304cd980e20))

## [0.7.0](https://github.com/Einlanzerous/argosy/compare/v0.6.0...v0.7.0) (2026-06-25)


### Features

* **mobile:** UI polish from Claude Design — account/Fleet sheet, framed hero, Manifest header (ARGY-92) ([#90](https://github.com/Einlanzerous/argosy/issues/90)) ([037f9e9](https://github.com/Einlanzerous/argosy/commit/037f9e97e363bc57b71da1ccdc8a6ca814a5d5d5))
* **series:** combined-episode files + per-episode TMDB metadata (ARGY-69 / ARGY-58) ([#92](https://github.com/Einlanzerous/argosy/issues/92)) ([28e105e](https://github.com/Einlanzerous/argosy/commit/28e105e5e1ac845a469f21781e8ebfd683ae9428))

## [0.6.0](https://github.com/Einlanzerous/argosy/compare/v0.5.0...v0.6.0) (2026-06-24)


### Features

* series auto-advance — auto-play next episode (web + Android) [ARGY-89 / ARGY-93] ([#86](https://github.com/Einlanzerous/argosy/issues/86)) ([f5c013a](https://github.com/Einlanzerous/argosy/commit/f5c013a0ecca416dabedde0930608bb408a31de0))


### Bug Fixes

* **scanner:** prune media for files that vanished on rescan (ARGY-96) ([#89](https://github.com/Einlanzerous/argosy/issues/89)) ([baf163c](https://github.com/Einlanzerous/argosy/commit/baf163c3af6d08095e4ab8b736e2fdb7da0c9314))
* **transcode:** keep session alive on progress heartbeat (ARGY-94) ([#87](https://github.com/Einlanzerous/argosy/issues/87)) ([4b3cbca](https://github.com/Einlanzerous/argosy/commit/4b3cbca94a26c08ca562f0d21ac839d6d16a2d59))

## [0.5.0](https://github.com/Einlanzerous/argosy/compare/v0.4.0...v0.5.0) (2026-06-22)


### Features

* **mobile:** Beacon SSE live sync for Continue-Watching (ARGY-48) ([#82](https://github.com/Einlanzerous/argosy/issues/82)) ([6d04d01](https://github.com/Einlanzerous/argosy/commit/6d04d0122907cd71d16ef0fc4025b23b1a252f13))
* **mobile:** browse surfaces — Bridge, Library, Search, Detail (ARGY-47) ([#79](https://github.com/Einlanzerous/argosy/issues/79)) ([6a6f6c5](https://github.com/Einlanzerous/argosy/commit/6a6f6c5fe69ec11de38c0fa278a172e0bddbaaea))
* **mobile:** Dart API client from OpenAPI + token storage (ARGY-78) ([#77](https://github.com/Einlanzerous/argosy/issues/77)) ([f6eb01d](https://github.com/Einlanzerous/argosy/commit/f6eb01d05040f36d1dd72ae2ff9120d4c09ca359))
* **mobile:** device auth / pairing flow (ARGY-46) ([#78](https://github.com/Einlanzerous/argosy/issues/78)) ([3771c5f](https://github.com/Einlanzerous/argosy/commit/3771c5f17153de3f1a657483418b3daabdc49bdf))
* **mobile:** Flutter app scaffold + Argosy theme + nav/state (ARGY-45) ([#75](https://github.com/Einlanzerous/argosy/issues/75)) ([0ada177](https://github.com/Einlanzerous/argosy/commit/0ada17766756232d81d00b923e11abc27579d37b))
* **mobile:** PiP, background audio + keep-screen-awake (ARGY-50) ([#84](https://github.com/Einlanzerous/argosy/issues/84)) ([b8c1226](https://github.com/Einlanzerous/argosy/commit/b8c12267536cdb452e086ae81c2e2f5797fbbbb5))
* **mobile:** player screen — transcode, controls, track selection, resume (ARGY-79) ([#80](https://github.com/Einlanzerous/argosy/issues/80)) ([a5dc30e](https://github.com/Einlanzerous/argosy/commit/a5dc30e952f24c725e67ddf16b94de567aa8f531))
* **mobile:** Settings screen — device/user prefs, profile switch (ARGY-80) ([#83](https://github.com/Einlanzerous/argosy/issues/83)) ([0a95b6b](https://github.com/Einlanzerous/argosy/commit/0a95b6b8dcbef3791f2b8e226eac9b09cc81900d))


### Bug Fixes

* **transcode:** keep A/V in sync on resumed remux path (ARGY-84) ([#81](https://github.com/Einlanzerous/argosy/issues/81)) ([e091835](https://github.com/Einlanzerous/argosy/commit/e091835ebf0d9866f1f9a4d79626953a6268b2d8))

## [0.4.0](https://github.com/Einlanzerous/argosy/compare/v0.3.1...v0.4.0) (2026-06-21)


### Features

* **discovery:** data-driven search chips + genre de-dup (ARGY-71) ([#65](https://github.com/Einlanzerous/argosy/issues/65)) ([bfd1759](https://github.com/Einlanzerous/argosy/commit/bfd175993795e9819c1358ec0b6e9ba660e368eb))
* **filters:** faceted browse — genre, rating, watched, year + rating sort ([#63](https://github.com/Einlanzerous/argosy/issues/63)) ([5d823f4](https://github.com/Einlanzerous/argosy/commit/5d823f4a4648c7bb6ccd97eaf01e4b68fe057792))
* **home:** Focused vs Discovery home layout ([#73](https://github.com/Einlanzerous/argosy/issues/73)) ([1578e00](https://github.com/Einlanzerous/argosy/commit/1578e00e02dfcf74f3cc79cab06bb24096c9d2e0))
* **home:** On Deck row + auto genre rows ([#67](https://github.com/Einlanzerous/argosy/issues/67)) ([e5aac83](https://github.com/Einlanzerous/argosy/commit/e5aac83cc7beab73b0bf6e39a785cc049233f639))
* **labels:** user-applied custom labels on films + series ([#74](https://github.com/Einlanzerous/argosy/issues/74)) ([8e8dfe2](https://github.com/Einlanzerous/argosy/commit/8e8dfe27c53923921ebded268edb07e31f793236))
* **libraries:** add/manage media libraries from Settings ([#70](https://github.com/Einlanzerous/argosy/issues/70)) ([0738235](https://github.com/Einlanzerous/argosy/commit/073823526063bfeee9d644e1caf0911237fd2fa6))
* **player:** closed-caption styling controls ([#71](https://github.com/Einlanzerous/argosy/issues/71)) ([bbebf00](https://github.com/Einlanzerous/argosy/commit/bbebf00acfa0959d1bfc4299890fb03cc3e64195))
* **search:** account-wide full-text search over The Manifest ([#61](https://github.com/Einlanzerous/argosy/issues/61)) ([8e877ae](https://github.com/Einlanzerous/argosy/commit/8e877ae6ea983c9d11b9ed4b180f12fe5e114d03))
* **vaults:** user-curated collections of films + series ([#68](https://github.com/Einlanzerous/argosy/issues/68)) ([ed5a054](https://github.com/Einlanzerous/argosy/commit/ed5a05448e15a16d06157ad313f3b6c30779168b))


### Bug Fixes

* **beacon:** preserve http.Flusher through the request-logging wrapper ([#66](https://github.com/Einlanzerous/argosy/issues/66)) ([0dd91b2](https://github.com/Einlanzerous/argosy/commit/0dd91b2503e255f745da7be6127e2b4d37328e76))
* **library:** collapsible filter panel + rating slider ([#69](https://github.com/Einlanzerous/argosy/issues/69)) ([08759ca](https://github.com/Einlanzerous/argosy/commit/08759cab2ec30cc2ed405bf288fec6cddf1dae9a))
* **vaults:** Add-to-Vault menu clipped by hero + button alignment ([#72](https://github.com/Einlanzerous/argosy/issues/72)) ([60cb050](https://github.com/Einlanzerous/argosy/commit/60cb050aa86805a110415a11fb1a8e3852213178))

## [0.3.1](https://github.com/Einlanzerous/argosy/compare/v0.3.0...v0.3.1) (2026-06-21)


### Bug Fixes

* **docker:** pin bun to 1.3.14 in the web build stage ([#58](https://github.com/Einlanzerous/argosy/issues/58)) ([f446f09](https://github.com/Einlanzerous/argosy/commit/f446f097c47e914f4c1e555d39d4567fb6153d26))
* **web:** add *.vue type shim so the Docker build's vue-tsc resolves SFCs ([#60](https://github.com/Einlanzerous/argosy/issues/60)) ([ee83da2](https://github.com/Einlanzerous/argosy/commit/ee83da2e743c8fe6a7c64d0c6d4623614ca31a48))

## [0.3.0](https://github.com/Einlanzerous/argosy/compare/v0.2.0...v0.3.0) (2026-06-21)


### Features

* **artwork:** fetch TMDB backdrops for crisp full-screen heroes ([#53](https://github.com/Einlanzerous/argosy/issues/53)) ([0d35de4](https://github.com/Einlanzerous/argosy/commit/0d35de46deebef20be254699843065c4fa8b3bd1))
* **auth:** enforce admin vs viewer roles (ARGY-38) ([#51](https://github.com/Einlanzerous/argosy/issues/51)) ([52658ae](https://github.com/Einlanzerous/argosy/commit/52658aed8a5e37d0bb9371ecfdcff99cf14c56d7))
* Ballast — transcode cache cleanup worker + stats (ARGY-32) ([#30](https://github.com/Einlanzerous/argosy/issues/30)) ([99becf6](https://github.com/Einlanzerous/argosy/commit/99becf6a0191201abc128227289b7d26ba91786f))
* **beacon:** live play-state push over Postgres LISTEN/NOTIFY → SSE (ARGY-36) ([#48](https://github.com/Einlanzerous/argosy/issues/48)) ([4cfeb51](https://github.com/Einlanzerous/argosy/commit/4cfeb515021ecbdff547c8d91f129f77f663780f))
* **fleet:** Fleet management — role-scoped device list, owner, platform, rename (ARGY-33) ([#46](https://github.com/Einlanzerous/argosy/issues/46)) ([b5e8e94](https://github.com/Einlanzerous/argosy/commit/b5e8e94fdfa05696f9d6d3149d2079168a070d71))
* HLS/CMAF bitrate ladder + web HLS playback (ARGY-28) ([#28](https://github.com/Einlanzerous/argosy/issues/28)) ([3a3f19a](https://github.com/Einlanzerous/argosy/commit/3a3f19a937f0db8ae24f07f8cb1f00324ce6daa3))
* **prefs:** per-device playback preferences (ARGY-37) ([#50](https://github.com/Einlanzerous/argosy/issues/50)) ([2c4f740](https://github.com/Einlanzerous/argosy/commit/2c4f7407aa771bbc9d80a92a34ec153c54851ceb))
* **presence:** live playback session model (ARGY-34) ([#47](https://github.com/Einlanzerous/argosy/issues/47)) ([06fee91](https://github.com/Einlanzerous/argosy/commit/06fee91b022881c66eb190042bcddaf80a71522c))
* **resume:** live cross-device resume sync via Beacon (ARGY-35) ([#49](https://github.com/Einlanzerous/argosy/issues/49)) ([736ff0d](https://github.com/Einlanzerous/argosy/commit/736ff0d01b29acf6cad1f519c179035b654e0d02))
* series detail — episode runtime + progress, series resume, even pill spacing ([#32](https://github.com/Einlanzerous/argosy/issues/32)) ([12cdda9](https://github.com/Einlanzerous/argosy/commit/12cdda98fc88595120fdb24318ef7932b56ad568))
* **subtitles:** embedded text + OpenSubtitles → WebVTT (ARGY-31) ([#35](https://github.com/Einlanzerous/argosy/issues/35)) ([c93cbef](https://github.com/Einlanzerous/argosy/commit/c93cbefe024ad55137dcb6bce6ad975af6771dfe))
* transcode decision engine — direct play → remux → transcode (ARGY-29) ([#29](https://github.com/Einlanzerous/argosy/issues/29)) ([8631d6c](https://github.com/Einlanzerous/argosy/commit/8631d6ccff84c6ad07c3bb31b6de60566e338250))
* transcode session orchestration — The Helm (ARGY-27) ([#26](https://github.com/Einlanzerous/argosy/issues/26)) ([e0a53dd](https://github.com/Einlanzerous/argosy/commit/e0a53ddadc031e23707d3b378376e27d507b8daf))
* **transcode:** HEVC output + per-client codec negotiation / true 4K (ARGY-62) ([#42](https://github.com/Einlanzerous/argosy/issues/42)) ([7326154](https://github.com/Einlanzerous/argosy/commit/73261545d07e100a84e13ce2fd874705c2951c3d))
* **transcode:** QSV hardware encode + software fallback (ARGY-30) ([#41](https://github.com/Einlanzerous/argosy/issues/41)) ([ef2b039](https://github.com/Einlanzerous/argosy/commit/ef2b039c90c4f0308af0d3291c04cbeb5faf5c85))
* **transcode:** VAAPI + NVENC encoder backends (ARGY-61) ([#43](https://github.com/Einlanzerous/argosy/issues/43)) ([e6c5437](https://github.com/Einlanzerous/argosy/commit/e6c5437a19c69c28e6204551fd479df876d2e75c))
* **web:** detail-page back button + resume/start-over ([#54](https://github.com/Einlanzerous/argosy/issues/54)) ([82619f9](https://github.com/Einlanzerous/argosy/commit/82619f96af1b3e41a4f6e63cb7734c557cb9ae82))
* **web:** drop the Shows rail from the home page ([#40](https://github.com/Einlanzerous/argosy/issues/40)) ([3685808](https://github.com/Einlanzerous/argosy/commit/368580846544be0e64225feb0247905aae312bd9))
* **web:** Newly Arrived includes series, not just films ([#44](https://github.com/Einlanzerous/argosy/issues/44)) ([bb44e82](https://github.com/Einlanzerous/argosy/commit/bb44e82022f53501b198483cf9af2afd572326bf))
* **web:** redesign series episode rows (name + runtime, progress line) ([#34](https://github.com/Einlanzerous/argosy/issues/34)) ([fff6f77](https://github.com/Einlanzerous/argosy/commit/fff6f770cc041866cbd996324fdc293223d147c0))


### Bug Fixes

* **fleet:** consistent device actions, green "this device" tag, rename/retire modals ([#52](https://github.com/Einlanzerous/argosy/issues/52)) ([31795b9](https://github.com/Einlanzerous/argosy/commit/31795b9b4ac8cf77c2c116fd9d3770613a761ec8))
* **web:** CC active outline + robust far-left "Playing on" placement ([#55](https://github.com/Einlanzerous/argosy/issues/55)) ([27b5bdc](https://github.com/Einlanzerous/argosy/commit/27b5bdc0d2c2411953c1bd59ff233328d3e8b1f3))
* **web:** correct player duration/seek, bigger controls, quality badge, humanize episode titles ([#31](https://github.com/Einlanzerous/argosy/issues/31)) ([a16ad23](https://github.com/Einlanzerous/argosy/commit/a16ad23dbd56a288758623b140ccfe30ef285b73))
* **web:** don't log out on transient auth-check failures ([#36](https://github.com/Einlanzerous/argosy/issues/36)) ([bc9a835](https://github.com/Einlanzerous/argosy/commit/bc9a835ae99dd8d517ba2ff6b03e45e65a5a1ea7))
* **web:** poster corner bleed + unified translucent brand pill ([#39](https://github.com/Einlanzerous/argosy/issues/39)) ([f761aa7](https://github.com/Einlanzerous/argosy/commit/f761aa78da5c055ad6ad5e0a7e45ca34e9230839))
* **web:** proxy /artwork in the vite dev server ([#38](https://github.com/Einlanzerous/argosy/issues/38)) ([c2dc495](https://github.com/Einlanzerous/argosy/commit/c2dc49585e2b5fbf14557519055e7fffe67413c3))
* **web:** Resume jumps straight in; only plain Play asks ([#33](https://github.com/Einlanzerous/argosy/issues/33)) ([e5a4d4b](https://github.com/Einlanzerous/argosy/commit/e5a4d4b37063df67d700a699e890f9df0cc16262))

## [0.2.0](https://github.com/Einlanzerous/argosy/compare/v0.1.0...v0.2.0) (2026-06-19)


### Features

* direct-play capability detection (ARGY-22) ([#24](https://github.com/Einlanzerous/argosy/issues/24)) ([1669a12](https://github.com/Einlanzerous/argosy/commit/1669a12c5be22c096f05d4003b75835c1bcbc94c))
* film/series classification + season/episode grouping (ARGY-17) ([#12](https://github.com/Einlanzerous/argosy/issues/12)) ([5e0d50b](https://github.com/Einlanzerous/argosy/commit/5e0d50bc0a9f392bdeadacc1c006154974428ff3))
* HTTP range-request media streaming — direct play (ARGY-21) ([#21](https://github.com/Einlanzerous/argosy/issues/21)) ([5a05bf1](https://github.com/Einlanzerous/argosy/commit/5a05bf1adb35ffb57cab4bea68e98e713822aa1c))
* library browse API — The Manifest (ARGY-20) ([#15](https://github.com/Einlanzerous/argosy/issues/15)) ([e330c2e](https://github.com/Einlanzerous/argosy/commit/e330c2e82bfc9bcf546086d99e07aae5977b9680))
* media scan foundation + ffprobe extraction (ARGY-16) ([#10](https://github.com/Einlanzerous/argosy/issues/10)) ([e4ca552](https://github.com/Einlanzerous/argosy/commit/e4ca552b1e1892a1c13c2fa9f452d892c2453cac))
* media tags + series/film taxonomy — anime as label (ARGY-54) ([#16](https://github.com/Einlanzerous/argosy/issues/16)) ([f7a1a04](https://github.com/Einlanzerous/argosy/commit/f7a1a0429340c518e4857bb718ab475f7f402eae))
* NFO/sidecar + local artwork overrides (ARGY-19) ([#14](https://github.com/Einlanzerous/argosy/issues/14)) ([252f0a0](https://github.com/Einlanzerous/argosy/commit/252f0a0d9cb72e26e926460b6b6a12500700dd53))
* periodic scan scheduler + scan status/trigger API (ARGY-15) ([#17](https://github.com/Einlanzerous/argosy/issues/17)) ([f7256a5](https://github.com/Einlanzerous/argosy/commit/f7256a563709d3bd8251565b86f729941c822f8a))
* play-state heartbeat + continue-watching; fix nested show naming (ARGY-24, ARGY-25) ([#22](https://github.com/Einlanzerous/argosy/issues/22)) ([00b507b](https://github.com/Einlanzerous/argosy/commit/00b507b6fd2f16a5093e6b2aad729db3111b6141))
* TMDB metadata matcher + artwork (ARGY-18) ([#13](https://github.com/Einlanzerous/argosy/issues/13)) ([0609439](https://github.com/Einlanzerous/argosy/commit/060943933611123ad50af179c103a27a7f917519))
* **web:** implement Argosy SPA from the Claude Design composition ([#18](https://github.com/Einlanzerous/argosy/issues/18)) ([481cedd](https://github.com/Einlanzerous/argosy/commit/481cedda87d3461bce480418027f5ffc63528a7c))
* **web:** real web player — direct play, heartbeat, resume, continue rail (ARGY-23) ([#23](https://github.com/Einlanzerous/argosy/issues/23)) ([59b394b](https://github.com/Einlanzerous/argosy/commit/59b394bb596f39fd2689e358189678fe94e1aff0))
* **web:** sleeker v2 chrome — floating top bar, cinematic home, search overlay ([#19](https://github.com/Einlanzerous/argosy/issues/19)) ([a550a2e](https://github.com/Einlanzerous/argosy/commit/a550a2e0231a3be627a88ad6427b5571557a3cb0))


### Bug Fixes

* JSON 404 for unknown /api paths; collapse Movies/Shows into Library (ARGY-55) ([#25](https://github.com/Einlanzerous/argosy/issues/25)) ([481194d](https://github.com/Einlanzerous/argosy/commit/481194d8b9be8823bfb266a376c7478a2ffc39c0))

## 0.1.0 (2026-06-18)


### Features

* account login + per-device tokens (ARGY-12) ([#7](https://github.com/Einlanzerous/argosy/issues/7)) ([8715c95](https://github.com/Einlanzerous/argosy/commit/8715c950713d38bc8ca2b82cafa21e964ddd4e3b))
* add PostgreSQL schema, migrations, and DB wiring (ARGY-11) ([#4](https://github.com/Einlanzerous/argosy/issues/4)) ([8962595](https://github.com/Einlanzerous/argosy/commit/8962595601593712a8cf597ce4634b6d4aa1d866))
* OpenAPI spec + codegen pipeline (ARGY-13) ([#6](https://github.com/Einlanzerous/argosy/issues/6)) ([09d81b2](https://github.com/Einlanzerous/argosy/commit/09d81b2492937fb3f8c8b38665e448dcbd2f1f2d))
