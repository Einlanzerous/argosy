# Argosy

Self-hosted media server for the Construct: catalog, transcode, playback, and a
paired-device fleet. A single Go binary with the Vue SPA embedded
(`internal/webui/dist`), plus a Flutter app for mobile and TV. Postgres for
state, HLS for delivery.

Tracked in Switchyard under the **ARGY** project.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

- ALWAYS read graphify-out/GRAPH_REPORT.md before reading any source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code, run `graphify update .` to keep *your local* graph current (AST-only, no API cost).
- **Never commit `graphify-out/` from a feature branch.** The directory is owned by
  `.github/workflows/graphify.yml`, which regenerates and commits it on every push
  to `main`. A branch that also commits it conflicts as soon as anything else
  merges — and at this repo's churn, something else always does (ARGY-185). Run
  the update locally for your own navigation; let CI publish it. If a rebase
  leaves `graphify-out/` dirty, discard it rather than resolving it by hand.
- If `graphify` is not installed: `uv tool install graphifyy==0.9.36` — match the
  version pinned in `graphify.yml`. An older local graphify rewrites the cache
  under its own version directory and deletes CI's, which looks like a 300-file
  deletion in your diff and silently downgrades the committed cache.
- To regenerate the report locally: `graphify extract .` then `graphify cluster-only . --no-viz --backend=claude` (0.9.x split the report out of extract; the explicit backend keeps community naming from being skipped — if you still see "Community N" placeholders, run `graphify label . --backend=claude`). Semantic extraction needs `ANTHROPIC_API_KEY`; CI refreshes the committed report + cache on every push to main.

## Layout

- `cmd/argosy/` — entrypoint. `internal/server/` wires the HTTP surface.
- `internal/auth/` — the permission surface: `accounts.go`, `owner.go`,
  `audit.go`, `link.go` (device pairing), middleware. **Read this before
  changing anything that touches who can see what.**
- `internal/db/migrations/` — numbered SQL, applied in order. `seed.sql` seeds dev.
- `internal/transcode/`, `internal/mediasource/`, `internal/subtitle/` — the
  playback path. Most of this repo's recurring bugs live here.
- `internal/library/`, `internal/metadata/` — catalog and enrichment.
- `web/` — Vue SPA, built into `internal/webui/dist` and embedded at compile time.
- `mobile/` — Flutter (Android/iOS/TV).
- `proto/openapi` — the API contract. A change here fans out to Go, Dart and TS.
- `deploy/` — Dockerfile and compose for the stack.

## Conventions

- Conventional commits with the ticket key in the subject:
  `fix(web): serve the SPA shell no-store and 404 stale chunks (ARGY-168)`.
  Scope is the subsystem — `web`, `player`, `transcode`, `mobile`, `auth`,
  `subtitle`, `fleet`, `detail`, `ci`. Branches are `type/argy-nnn-slug`.
- Release-please owns `CHANGELOG.md` and versions. Don't hand-edit.
- `make build` is web-build then go-build; the SPA must exist before the Go
  binary compiles (`ensure-embed` guarantees a non-empty embed dir).

## Invariants — don't break these

- **Audit writes must outlive the request.** `internal/auth/audit.go` detaches
  from the request context with `context.WithoutCancel`, because a client
  disconnecting between the committed mutation and the audit INSERT loses the
  row — the exact accountability gap the trail exists to close. Any new audited
  action inherits this; don't hand it the request context.
- **A wrong current password answers 403, never 401.** A 401 tells the client
  its token is dead and signs the device out, so returning it for a bad
  password logs someone out of a device that was fine. Easy to undo by reaching
  for the more obvious status code.
- **Reset revokes devices; self-serve change does not.** Changing your own
  password proves you hold the current one. An owner-driven *reset* means the
  credential was lost or leaked, and a leaked password may already have paired
  a device — so a reset revokes the account's device tokens while a change
  leaves the Fleet signed in.
- **`DeleteAccount` refuses an account that still owns library rows.** Pre-
  ARGY-167 data exists where the ownership backfill never moved
  `libraries.account_id`, and the cascade would take catalog items with the
  account, silently. Guard first, delete second.
- **Instance ownership means members browse the owner's catalog** (ARGY-167).
  Ownership is instance-level, not per-library — check which one a change is
  actually keying on before assuming.
- **Secure-context browser APIs are unavailable here.** Argosy is reached over
  plain HTTP by hostname on the tailnet (`imperial-construct:5173`), so
  `crypto.randomUUID` — and anything else gated on a secure context — throws at
  runtime. Use `crypto.getRandomValues`. This broke sign-in and fleet-add once
  (ARGY-121), and the failure is invisible on localhost.
- **Playlists and the SPA shell must be uncacheable.** `http.ServeFile` answers
  `If-Modified-Since` from ModTime at one-second granularity, and a fast remux
  writes the partial and the final (`ENDLIST`) playlist inside the same second —
  so a client that fetched the partial got a stale 304 and wedged (ARGY-106).
  The same class hit the SPA: stale chunks must 404 rather than resolve, and the
  shell must be `no-store`, or a deploy breaks browser Back (ARGY-164/168).
- **Transcode sessions are reaped.** The player must survive a session vanishing
  underneath it, and must keep the session alive while paused (ARGY-107). New
  playback paths need both.

## Testing

CI is thorough here — more so than the other repos in the estate.

| Workflow / job | Runs |
|---|---|
| `ci.yml` / `go` | `go vet`, `gofmt -l`, `golangci-lint`, `make test` (= `go test ./cmd/... ./internal/...`, all 47 test files) against a `postgres` service with `ffmpeg` installed, then `make go-build` |
| `ci.yml` / `web` | `bun run format:check`, `lint`, `build` |
| `ci.yml` / `openapi-drift` | `make generate` + `git diff --exit-code` — regenerating the contract's consumers is enforced, not remembered |
| `mobile.yml` | `flutter analyze`, `flutter test`, debug APK, iOS build |

`make test` needs `ARGOSY_TEST_DATABASE_URL`; CI provides it from the service
container. Locally, `make test` after `make ensure-embed`.

What CI cannot see is what the invariants above are for: ownership semantics,
cache and staleness behaviour, secure-context browser APIs, and playback
lifecycle across a reaped transcode session. Every one of those was learned from
a bug that shipped green.
