package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/version"
	"github.com/jackc/pgx/v5/pgxpool"
)

// What the delivery reconciler actually parses. Decoded into a raw map rather
// than into healthResponse so this asserts the JSON *wire* shape — reusing the
// struct would make a renamed json tag invisible, which is exactly the break
// that would silently stop observations.
func decodeHealthz(t *testing.T, body []byte) map[string]any {
	t.Helper()
	var got map[string]any
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatalf("body is not JSON: %v (body=%s)", err, body)
	}
	return got
}

func stampVersion(t *testing.T, v, commit string) {
	t.Helper()
	origVersion, origCommit := version.Version, version.Commit
	t.Cleanup(func() { version.Version, version.Commit = origVersion, origCommit })
	version.Version, version.Commit = v, commit
}

const testSHA = "5611a6c78a11e5f04a1c087c8cb9c2c138a3e8d5"

func TestHealthzReportsBuildIdentity(t *testing.T) {
	stampVersion(t, "0.25.1", testSHA)

	rec := httptest.NewRecorder()
	healthHandler(nil)(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", rec.Code)
	}
	// Checked as a prefix: httpx.JSON appends "; charset=utf-8". What matters is
	// that it is no longer text/plain — the reconciler read this endpoint's old
	// bare "ok" as "speaks, but reports no version", which is the whole reason
	// for the change. It also sniffs a leading "<" when the header is absent and
	// files a markup body as `unreachable`.
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Errorf("Content-Type = %q, want application/json", ct)
	}

	got := decodeHealthz(t, rec.Body.Bytes())
	if got["status"] != "ok" {
		t.Errorf("status = %v, want ok", got["status"])
	}
	if got["version"] != "0.25.1" {
		t.Errorf("version = %v, want bare semver 0.25.1", got["version"])
	}
	if got["sha"] != testSHA {
		t.Errorf("sha = %v, want the full 40-char commit %s", got["sha"], testSHA)
	}
}

// The distinctive half of argosy's contract, and the reason /healthz was chosen
// over /api/v1/ping: this endpoint really does go 503 when Postgres is
// unreachable, and that is exactly when someone wants the build named. The body
// shape must be IDENTICAL to the 200 — a degraded service is still running a
// version.
func TestHealthzCarriesIdentityOnThe503Path(t *testing.T) {
	stampVersion(t, "0.25.1", testSHA)

	// A pool pointed at a port nothing listens on. pgxpool does not dial on
	// construction, so this yields a live *Pool whose Ping fails — which is the
	// state the handler branches on.
	cfg, err := pgxpool.ParseConfig("postgres://nobody@127.0.0.1:1/none?sslmode=disable")
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}
	cfg.MinConns = 0
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("NewWithConfig: %v", err)
	}
	t.Cleanup(pool.Close)

	rec := httptest.NewRecorder()
	healthHandler(pool)(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 with the database unreachable", rec.Code)
	}

	got := decodeHealthz(t, rec.Body.Bytes())
	if got["status"] != "degraded" {
		t.Errorf("status = %v, want degraded", got["status"])
	}
	// The assertion the whole 503 rule exists for.
	if got["version"] != "0.25.1" {
		t.Errorf("version = %v on the 503 path, want 0.25.1 — the identity must survive a degraded dependency", got["version"])
	}
	if got["sha"] != testSHA {
		t.Errorf("sha = %v on the 503 path, want %s", got["sha"], testSHA)
	}
}

// An unstamped build must say "dev", and `sha` must be JSON null rather than "".
func TestHealthzUnstampedBuild(t *testing.T) {
	// Exactly what an image built with no --build-arg produces.
	stampVersion(t, "", "")

	rec := httptest.NewRecorder()
	healthHandler(nil)(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	got := decodeHealthz(t, rec.Body.Bytes())
	if got["version"] != "dev" {
		t.Errorf("version = %v, want dev — a blank ARG must not report an empty version", got["version"])
	}
	if _, present := got["sha"]; !present {
		t.Error("sha key is missing; the contract wants it present and null")
	}
	if got["sha"] != nil {
		t.Errorf("sha = %v, want null", got["sha"])
	}
}
