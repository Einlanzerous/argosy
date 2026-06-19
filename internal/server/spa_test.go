package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
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
