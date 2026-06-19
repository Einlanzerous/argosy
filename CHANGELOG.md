# Changelog

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
