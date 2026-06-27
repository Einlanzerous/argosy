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

func TestTMDBSeasonEpisodes(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/tv/222/season/1" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"episodes":[
			{"episode_number":1,"name":"Everything Is Fine","overview":"Eleanor arrives.","still_path":"/e1.jpg"},
			{"episode_number":2,"name":"Flying","overview":"She tries to be good.","still_path":""}
		]}`))
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "")
	tm.baseURL = srv.URL
	tm.imageBase = "https://img"

	eps, err := tm.SeasonEpisodes(context.Background(), 222, 1)
	if err != nil {
		t.Fatalf("season episodes: %v", err)
	}
	if len(eps) != 2 {
		t.Fatalf("got %d episodes, want 2", len(eps))
	}
	if eps[0].Number != 1 || eps[0].Name != "Everything Is Fine" || eps[0].StillURL != "https://img/w300/e1.jpg" {
		t.Errorf("ep1 = %+v", eps[0])
	}
	if eps[1].Name != "Flying" || eps[1].StillURL != "" { // no still_path → no URL
		t.Errorf("ep2 = %+v", eps[1])
	}
}

func TestTMDBMovieCredits(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/movie/12345/credits" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"cast":[{"name":"Bruce Willis"},{"name":"Alan Rickman"},{"name":""},{"name":"Bruce Willis"}],
			"crew":[{"name":"John McTiernan","job":"Director"},{"name":"Jan de Bont","job":"Director of Photography"}]
		}`))
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "")
	tm.baseURL = srv.URL

	cast, err := tm.MovieCredits(context.Background(), 12345)
	if err != nil {
		t.Fatalf("credits: %v", err)
	}
	// Top-billed cast in order, blanks + dupes dropped, director appended (the
	// non-director crew member is excluded).
	want := []string{"Bruce Willis", "Alan Rickman", "John McTiernan"}
	if len(cast) != len(want) {
		t.Fatalf("cast = %v, want %v", cast, want)
	}
	for i, n := range want {
		if cast[i] != n {
			t.Errorf("cast[%d] = %q, want %q", i, cast[i], n)
		}
	}
}

func TestTMDBSeriesCreditsCap(t *testing.T) {
	// 20 cast members → capped at castLimit, no crew on series.
	var cast string
	for i := 0; i < 20; i++ {
		if i > 0 {
			cast += ","
		}
		cast += `{"name":"Actor ` + string(rune('A'+i)) + `"}`
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/tv/222/credits" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"cast":[` + cast + `],"crew":[{"name":"Showrunner X","job":"Director"}]}`))
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "")
	tm.baseURL = srv.URL

	got, err := tm.SeriesCredits(context.Background(), 222)
	if err != nil {
		t.Fatalf("credits: %v", err)
	}
	if len(got) != castLimit {
		t.Fatalf("series cast = %d names, want castLimit %d", len(got), castLimit)
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
