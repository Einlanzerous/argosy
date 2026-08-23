// Package version carries this build's identity: the release it was cut from
// and the commit it was built at.
//
// Both are injected at link time by deploy/Dockerfile:
//
//	-ldflags "-X github.com/Einlanzerous/argosy/internal/version.Version=0.25.1 \
//	          -X github.com/Einlanzerous/argosy/internal/version.Commit=<40-char sha>"
//
// ── Why the values are never guessed ───────────────────────────────────────
//
// These two feed `GET /healthz`, which Switchyard's delivery reconciler polls to
// record what is actually running (SWY-192, rolled out by SERV-128). An
// observation is the half of the delivery ledger that is supposed to be
// trustworthy — a report says what someone MEANT to deploy, an observation says
// what answered. A process that reports a plausible-looking version it did not
// ship becomes a real row in that ledger, indistinguishable from a real deploy.
//
// So an unstamped build says "dev" and an unknown commit says nothing at all.
// Neither is ever inferred from go.mod, a VCS stamp, or the image tag.
package version

// DevVersion is what a build that was not cut by a release reports.
const DevVersion = "dev"

// Version is the release this binary was built from — bare semver, no "v"
// prefix. Overwritten at link time; "dev" for a local `go build`.
//
// The bare form is load-bearing rather than cosmetic. Switchyard compares this
// string with strict equality against `org.opencontainers.image.version`, which
// docker/metadata-action stamps WITHOUT the prefix. Report "v0.25.1" against a
// label of "0.25.1" and every deploy report is filed `claimed_not_confirmed`
// for ever — a permanent red row on the one page whose job is to be believed.
var Version = DevVersion

// Commit is the full 40-character commit sha this binary was built at, or ""
// when the build supplied none. Reported verbatim: abbreviating it here would
// turn the cross-service comparison into a prefix problem.
var Commit = ""

// ── Read these through Get(), never directly ──────────────────────────────
//
// `Version` and `Commit` are the RAW linker inputs, and a blank build links an
// empty string into both — over the defaults above, not instead of them. Only
// `Get()` applies the blank-to-dev rule, so a caller that reads `Version`
// directly reports "" where it means "dev".
//
// That is not hypothetical: every reader in this repo was doing exactly that
// before the health contract landed, and it was invisible while the Docker ARG
// still defaulted to a non-empty placeholder. Emptying that default is what
// made the bypass reachable.
//
// They stay exported because `Get()`'s rule has to be exercised from sibling
// packages' tests. Treat that as a seam for tests, not a public read path.

// Identity is the (version, sha) pair as /healthz reports it.
//
// `sha` is a *string pointer so an absent commit marshals to JSON `null` rather
// than `""`. Absence is a value here — "this build did not record a commit" is
// a different claim from "this build was made at the empty commit", and the
// consumer treats a blank string as no-version-reported.
type Identity struct {
	Version string  `json:"version"`
	SHA     *string `json:"sha"`
}

// Get resolves what this build honestly reports.
//
// The blank-is-not-unset rule (SWY-224, and the estate's oldest invariant): a
// Docker `ARG` that is declared but never passed expands to an EMPTY STRING, so
// `-X ...Version=` links in "" rather than leaving the default in place. Without
// the fallback below, an image built outside the release workflow would report a
// version of "" — not a crash, just a silently wrong answer propagated into
// every consumer of the contract.
func Get() Identity {
	v := Version
	if v == "" {
		v = DevVersion
	}
	var sha *string
	if Commit != "" {
		c := Commit
		sha = &c
	}
	return Identity{Version: v, SHA: sha}
}
