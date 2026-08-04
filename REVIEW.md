# Review instructions

Review-only guidance, higher priority than `CLAUDE.md`. `CLAUDE.md` describes
how this repo works; this file describes what a review of it is *for*.

## What this review is for

Know precisely what CI covers before leaning on it, because here it is less
than it looks. `ci.yml` runs **`go vet` and `bun run lint` — that is all for the
backend and web.** `mobile.yml` runs `flutter analyze` and `flutter test`.

**`go test` runs in no workflow.** There are 47 `_test.go` files under `cmd/`
and `internal/`, including the auth package's account, owner, middleware and
audit tests. None execute in CI. So a change to accounts, ownership, device
pairing, transcode or subtitles is checked by `go vet` and a human, and by
nothing else.

Assume `go vet`, `bun run lint`, and the Flutter analyze/test pass. Assume
nothing about Go behaviour. That inverts the usual rule: **for Go changes the
tests existing is not evidence they ran**, so reason through the change rather
than deferring to a green check.

## Ticket fidelity — check this first

When a Switchyard ticket is linked, read its description and exit criteria
before the diff, and answer explicitly in the summary:

- Does the implementation satisfy the stated exit criteria, or only the easy
  subset of them?
- Did a requirement get silently dropped, narrowed, or deferred without saying?
- Does the PR claim something is verified that the diff does not demonstrate?
  Here that is sharper than usual: a PR saying "added tests" has added files CI
  will not run.

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

**Contract changes** — `proto/openapi` fans out to Go, Dart and TypeScript.
Does the diff regenerate all three consumers, or only the one being worked on?

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
