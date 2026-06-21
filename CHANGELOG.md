# Changelog

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
