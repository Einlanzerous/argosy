package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/health"
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

	pool := unreachablePool(t)

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

// unreachablePool yields a live *Pool whose Ping fails: it points at a port
// nothing listens on, and pgxpool does not dial on construction. That is the
// state healthHandler branches on to answer 503.
func unreachablePool(t *testing.T) *pgxpool.Pool {
	t.Helper()
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
	return pool
}

// ── The container healthcheck, end to end (ARGY-216) ───────────────────────
//
// The image's HEALTHCHECK is `argosy healthcheck`, which is internal/health's
// Probe pointed at this handler. The two are written in different packages
// against a contract that is only text, so this drives the REAL handler through
// the REAL probe rather than either against a fake — a renamed json tag or a
// changed status word would otherwise sail past both packages' own tests and
// leave every argosy container permanently unhealthy (or, far worse, wedge the
// probe healthy) with nothing red until someone looked.
//
// CLAUDE.md's bar for a new healthcheck is that it can be *seen* to fail. These
// two tests are the standing half of that; the other half is taking a running
// container's database away and watching the status flip, which is where this
// one was confirmed.
func TestHealthcheckProbeAgreesWithTheHandler(t *testing.T) {
	stampVersion(t, "0.27.2", testSHA)

	srv := httptest.NewServer(healthHandler(nil))
	defer srv.Close()

	rep, err := health.Probe(context.Background(), srv.Client(), srv.URL+"/healthz")
	if err != nil {
		t.Fatalf("the probe called a healthy handler unhealthy: %v", err)
	}
	if rep.Status != health.StatusOK {
		t.Errorf("status = %q, want %q", rep.Status, health.StatusOK)
	}
	if rep.Version != "0.27.2" {
		t.Errorf("version = %q, want 0.27.2 — the probe reads identity off the same body", rep.Version)
	}
}

func TestHealthcheckProbeGoesUnhealthyWhenTheDatabaseIs(t *testing.T) {
	stampVersion(t, "0.27.2", testSHA)

	srv := httptest.NewServer(healthHandler(unreachablePool(t)))
	defer srv.Close()

	rep, err := health.Probe(context.Background(), srv.Client(), srv.URL+"/healthz")
	if err == nil {
		t.Fatal("the probe reported healthy with the database unreachable — this is the state the healthcheck exists to surface")
	}
	// Still names the build, so `docker inspect`'s health log says which one.
	if rep.Version != "0.27.2" {
		t.Errorf("version = %q on the unhealthy path, want 0.27.2", rep.Version)
	}
}
