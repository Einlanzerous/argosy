package metadata

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestTMDBSearchMovie(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/search/movie" {
			http.NotFound(w, r)
			return
		}
		if r.Header.Get("Authorization") != "Bearer test-token" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"results":[{"id":12345,"title":"Big Buck Bunny","overview":"A bunny.","poster_path":"/poster.jpg","backdrop_path":"/backdrop.jpg","release_date":"2008-05-30","genre_ids":[16,35]}]}`))
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "")
	tm.baseURL = srv.URL
	tm.imageBase = "https://img"

	m, err := tm.SearchMovie(context.Background(), "Big Buck Bunny", 2008)
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if m == nil {
		t.Fatal("expected a match")
	}
	if m.TMDBID != 12345 || m.Title != "Big Buck Bunny" || m.Year != 2008 {
		t.Errorf("match = %+v", m)
	}
	if m.PosterURL != "https://img/w780/poster.jpg" {
		t.Errorf("poster = %q", m.PosterURL)
	}
	if m.BackdropURL != "https://img/w1280/backdrop.jpg" {
		t.Errorf("backdrop = %q", m.BackdropURL)
	}
}

func TestTMDBNoResults(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"results":[]}`))
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "")
	tm.baseURL = srv.URL
	m, err := tm.SearchSeries(context.Background(), "Nonexistent Show")
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if m != nil {
		t.Errorf("expected nil match, got %+v", m)
	}
}

func TestTMDBConfigured(t *testing.T) {
	if NewTMDB("", "").Configured() {
		t.Error("empty creds should be unconfigured")
	}
	if !NewTMDB("", "apikey").Configured() {
		t.Error("api key should be configured")
	}
}
