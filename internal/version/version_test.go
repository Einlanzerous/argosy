package version

import "testing"

// The blank-vs-unset rule is the whole reason Get() exists rather than callers
// reading Version and Commit directly, so it is what these tests pin down.
//
// A Docker `ARG` that is declared but never passed expands to an EMPTY STRING,
// and `-ldflags -X pkg.Version=` links that empty string in — overwriting the
// "dev" default. Nothing crashes; the service just reports a version of "" into
// the delivery ledger for ever. That is the failure worth a test.
func TestGet(t *testing.T) {
	// Restored rather than assumed: these are package-level vars, so a test
	// that leaves them mutated corrupts every test after it.
	origVersion, origCommit := Version, Commit
	t.Cleanup(func() { Version, Commit = origVersion, origCommit })

	const sha = "5611a6c78a11e5f04a1c087c8cb9c2c138a3e8d5"

	tests := []struct {
		name        string
		version     string
		commit      string
		wantVersion string
		wantSHA     *string
	}{
		{
			name:        "unstamped build reports dev and no sha",
			version:     DevVersion,
			commit:      "",
			wantVersion: "dev",
			wantSHA:     nil,
		},
		{
			// The case that actually bites: ARG declared, never passed.
			name:        "blank version falls through to dev",
			version:     "",
			commit:      "",
			wantVersion: "dev",
			wantSHA:     nil,
		},
		{
			name:        "blank commit is absent, not empty",
			version:     "0.25.1",
			commit:      "",
			wantVersion: "0.25.1",
			wantSHA:     nil,
		},
		{
			name:        "a release build reports both",
			version:     "0.25.1",
			commit:      sha,
			wantVersion: "0.25.1",
			wantSHA:     strptr(sha),
		},
		{
			// Not normalised here on purpose. A "v" prefix is a bug in the
			// BUILD (the workflow passed github.ref_name instead of the bare
			// semver), and silently stripping it would hide that from the one
			// place it is visible. This test records that Get() is a reporter,
			// not a sanitiser — see the package doc for why the bare form
			// matters.
			name:        "the version is reported verbatim",
			version:     "v0.25.1",
			commit:      sha,
			wantVersion: "v0.25.1",
			wantSHA:     strptr(sha),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			Version, Commit = tt.version, tt.commit
			got := Get()

			if got.Version != tt.wantVersion {
				t.Errorf("Version = %q, want %q", got.Version, tt.wantVersion)
			}
			switch {
			case tt.wantSHA == nil && got.SHA != nil:
				t.Errorf("SHA = %q, want nil — an absent commit must marshal to JSON null, not \"\"", *got.SHA)
			case tt.wantSHA != nil && got.SHA == nil:
				t.Errorf("SHA = nil, want %q", *tt.wantSHA)
			case tt.wantSHA != nil && *got.SHA != *tt.wantSHA:
				t.Errorf("SHA = %q, want %q", *got.SHA, *tt.wantSHA)
			}
		})
	}
}

// The sha is returned as a pointer into a local copy, not into the package var,
// so a caller cannot reach through Identity and mutate Commit.
func TestGetDoesNotAliasPackageState(t *testing.T) {
	origVersion, origCommit := Version, Commit
	t.Cleanup(func() { Version, Commit = origVersion, origCommit })

	Version, Commit = "0.25.1", "abc123"
	got := Get()
	if got.SHA == nil {
		t.Fatal("SHA = nil, want a value")
	}
	*got.SHA = "tampered"
	if Commit != "abc123" {
		t.Errorf("Commit = %q after mutating the returned pointer, want it untouched", Commit)
	}
}

func strptr(s string) *string { return &s }
