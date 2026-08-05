# Review instructions

Review-only guidance, higher priority than `CLAUDE.md`. `CLAUDE.md` describes
how this repo works; this file describes what a review of it is *for*.

## What this review is for

Argosy has the strongest CI in the estate. Lean on it, and do not spend the
review re-proving what it already proves:

| job | proves |
|---|---|
| `ci.yml` / `go` (with a `postgres` service and `ffmpeg`) | `go vet`, `gofmt -l`, `golangci-lint`, **`make test` — every one of the 47 `_test.go` files under `cmd/` and `internal/`, including all four of `internal/auth/`'s** — and that the binary builds |
| `ci.yml` / `web` | `format:check`, `lint`, `build` |
| `ci.yml` / `openapi-drift` | `make generate` then `git diff --exit-code` — a `proto/openapi` change that did not regenerate its Go, Dart and TS consumers fails the build |
| `mobile.yml` | `flutter analyze`, `flutter test`, debug APK and iOS builds |

Assume all of that passed. A green `ci` means the Go tests ran against a real
Postgres, not that test files merely exist.

So the review's job here is narrow and specific: **the classes of bug this repo
keeps shipping despite that CI.** Every invariant in `CLAUDE.md` was learned
from a `fix(...)` commit that got past exactly this pipeline. Ownership
semantics that compile and pass their tests but grant the wrong person access;
caching and staleness, which no unit test observes; browser APIs that work in CI
and throw on the tailnet; playback lifecycle across a reaped session. Those are
where attention belongs.

## Ticket fidelity — check this first

When a Switchyard ticket is linked, read its description and exit criteria
before the diff, and answer explicitly in the summary:

- Does the implementation satisfy the stated exit criteria, or only the easy
  subset of them?
- Did a requirement get silently dropped, narrowed, or deferred without saying?
- Does the PR claim something is verified that the diff does not demonstrate?
  Note the shape this takes here: CI runs the tests, so "added tests" is
  credible — what it does not tell you is whether the test asserts the thing the
  ticket asked for. A passing test of the wrong behaviour is still a finding.

A change that is clean code and wrong scope is a **🔴 Important** finding. Say
which criterion is unmet and quote it.

When no ticket is linked, say so in one line and review the diff on its own
terms. Do not invent intent from the branch name.

## Severity

- **🔴 Important** — breaks playback or the catalog, widens who can see whose
  media, loses or corrupts data, wedges a client until cache expiry, or does not
  do what the ticket asked.
- **🟡 Nit** — conventions, clarity, a comment that will mislead. Never blocking.
- **🟣 Pre-existing** — real, not introduced here. At most two per review.

Cap nits at five; beyond that say "plus N similar" in the summary. A review that
buries one Important finding under twelve nits has failed at its job.

## Always check

**Auth and ownership** — the highest-value area, and where the invariants were
learned the hard way. `internal/auth/`.

- Does a new audited action pass the *request* context to the audit write? It
  must detach (`context.WithoutCancel`), or a client disconnect drops the row.
- Does a credential path return 401 where 403 is meant? 401 signs the device out.
- Does a destructive account operation guard the rows it would cascade into?
- Does a change key on per-library ownership where the model is instance-level,
  or the reverse?
- Does a new endpoint scope reads to what the caller may see, rather than
  assuming the caller is the owner?

**Caching and staleness** — this repo's most repeated bug class.

- Does a new file-serving path use `http.ServeFile` for content that changes
  within a second? That returns stale 304s and wedges clients.
- Do new SPA assets get content-hashed names, and does the shell stay
  `no-store`? A stale chunk that resolves instead of 404ing breaks navigation
  after a deploy.

**Browser environment** — the web UI runs over plain HTTP on the tailnet.

- Does new web code call a secure-context-only API (`crypto.randomUUID`,
  clipboard, service workers)? It will throw in the environment users are in,
  and work perfectly on localhost.

**Playback lifecycle** — transcode sessions are reaped.

- Does a new player path handle its session disappearing, and keep it alive
  while paused?

**Migrations** — `internal/db/migrations/` is applied in order at startup. Is
the change additive, and is it safe against the pre-ARGY-167 data the ownership
backfill did not move?

## Verification bar

Report a finding only when you can point at the line that causes it and name
the concrete failure — the input, state, or sequence that produces the wrong
outcome. "This could be risky" is not a finding.

Behaviour inferred from a name is not evidence. If you find yourself writing
"this may not handle…", go read the implementation or drop it. For auth
findings specifically, trace the actual call path: a handler that looks
unguarded is sometimes guarded in middleware.

## Re-reviews

Round three should be shorter than round one. After the first review of a PR:
report **new Important findings only**. No new nits, no restating open
findings, no re-raising something the author explicitly declined. Note in one
line what got fixed, then move on.

## Summary shape

Open with a one-line tally — `2 important, 1 nit` — or **No blocking issues**.
Then ticket fidelity in a sentence. Then findings, most severe first.

If the diff is clean, say so in one line and stop. Do not pad.
