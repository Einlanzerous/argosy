package server

import (
	"io/fs"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/webui"
)

func TestSPAHandlerAPINotFound(t *testing.T) {
	spa, err := newSPAHandler()
	if err != nil {
		t.Fatalf("newSPAHandler: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/does-not-exist", nil)
	rec := httptest.NewRecorder()
	spa.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Errorf("Content-Type = %q, want application/json", ct)
	}
	if !strings.Contains(rec.Body.String(), `"error"`) {
		t.Errorf("body = %q, want a JSON error", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "<!doctype html>") {
		t.Error("unmatched /api/ path served the SPA shell")
	}
}

func TestSPAHandlerFallsBackForNonAPI(t *testing.T) {
	spa, err := newSPAHandler()
	if err != nil {
		t.Fatalf("newSPAHandler: %v", err)
	}

	// A client-side route should not 404 — it falls back to the SPA shell (or
	// the "not built yet" placeholder when dist is empty). Either way: not 404.
	req := httptest.NewRequest(http.MethodGet, "/library", nil)
	rec := httptest.NewRecorder()
	spa.ServeHTTP(rec, req)

	if rec.Code == http.StatusNotFound {
		t.Fatalf("non-API path returned 404; want SPA fallback")
	}
}

// TestSPAHandlerStaleAssetIs404 covers the ARGY-168 root cause: a tab that
// predates a deploy asks for a chunk hash that no longer exists. Falling back to
// the SPA shell answered 200 text/html for a .js URL, which browsers reject as a
// MIME violation ("Loading module ... was blocked because of a disallowed MIME
// type") rather than reporting a plain miss.
func TestSPAHandlerStaleAssetIs404(t *testing.T) {
	spa, err := newSPAHandler()
	if err != nil {
		t.Fatalf("newSPAHandler: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/assets/VaultsView-Dn8wge1_.js", nil)
	rec := httptest.NewRecorder()
	spa.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 for a missing build asset", rec.Code)
	}
	if strings.Contains(strings.ToLower(rec.Body.String()), "<!doctype html>") {
		t.Error("missing asset served the SPA shell; browsers reject that as a module MIME error")
	}
}

// TestSPAHandlerCaching pins the two caching rules a deploy depends on: the
// shell must never be cached (it is the only document naming current chunk
// hashes, so a stale copy defeats the router's recovery reload), while
// content-hashed assets are immutable.
func TestSPAHandlerCaching(t *testing.T) {
	spa, err := newSPAHandler()
	if err != nil {
		t.Fatalf("newSPAHandler: %v", err)
	}

	for _, p := range []string{"/", "/library", "/settings"} {
		rec := httptest.NewRecorder()
		spa.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, p, nil))
		if cc := rec.Header().Get("Cache-Control"); !strings.Contains(cc, "no-store") {
			t.Errorf("%s Cache-Control = %q, want no-store", p, cc)
		}
	}

	// Assets exist only once the SPA has been built; when dist is empty (CI
	// before `vite build`) there is nothing to assert beyond the 404 rule.
	sub, err := webui.FS()
	if err != nil {
		t.Fatalf("webui.FS: %v", err)
	}
	entries, err := fs.ReadDir(sub, "assets")
	if err != nil || len(entries) == 0 {
		t.Skip("no built assets embedded; skipping immutable-caching assertion")
	}
	var asset string
	for _, e := range entries {
		if !e.IsDir() {
			asset = e.Name()
			break
		}
	}
	rec := httptest.NewRecorder()
	spa.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/assets/"+asset, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("asset %s status = %d, want 200", asset, rec.Code)
	}
	if cc := rec.Header().Get("Cache-Control"); !strings.Contains(cc, "immutable") {
		t.Errorf("asset Cache-Control = %q, want immutable", cc)
	}
}
