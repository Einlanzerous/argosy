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

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL, ImageBaseURL: "https://img"})

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

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL, ImageBaseURL: "https://img"})

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

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})

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

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})

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

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	m, err := tm.SearchSeries(context.Background(), "Nonexistent Show")
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if m != nil {
		t.Errorf("expected nil match, got %+v", m)
	}
}

func TestTMDBConfigured(t *testing.T) {
	if NewTMDB("", "", TMDBOptions{}).Configured() {
		t.Error("empty creds should be unconfigured")
	}
	if !NewTMDB("", "apikey", TMDBOptions{}).Configured() {
		t.Error("api key should be configured")
	}
}

// episodeGroupServer serves the two documents AlternateSeasonMap reads, shaped
// like TMDB's real answer for Bleach (tv/30984): a "TVDB Order" group whose
// ordinals are the season numbers Sonarr laid the files out under.
func episodeGroupServer(t *testing.T, groupsJSON, detailJSON string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/tv/30984/episode_groups":
			_, _ = w.Write([]byte(groupsJSON))
		case "/tv/episode_group/tvdb-order":
			_, _ = w.Write([]byte(detailJSON))
		default:
			http.NotFound(w, r)
		}
	}))
}

func TestTMDBSeriesSeasons(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/tv/30984" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"seasons":[
			{"season_number":0,"name":"Specials","episode_count":4},
			{"season_number":1,"name":"Bleach","episode_count":366},
			{"season_number":2,"name":"Thousand-Year Blood War","episode_count":50}
		]}`))
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.SeriesSeasons(context.Background(), 30984)
	if err != nil {
		t.Fatalf("series seasons: %v", err)
	}
	if len(got) != 3 {
		t.Fatalf("got %d seasons, want 3", len(got))
	}
	if got[2].Number != 2 || got[2].Name != "Thousand-Year Blood War" || got[2].EpisodeCount != 50 {
		t.Errorf("season 2 = %+v", got[2])
	}
	// Nothing numbered 17 — which is exactly why season 17 on disk went empty.
	for _, s := range got {
		if s.Number == 17 {
			t.Fatal("provider reported a season 17; the fixture is wrong")
		}
	}
}

// TestTMDBAlternateSeasonMap pins ARGY-224's translation: TVDB's season 17 is
// TMDB's season 2 at no offset, while TVDB's season 3 lands *inside* TMDB's
// season 1 at episode 42 — the case a season number alone cannot express.
func TestTMDBAlternateSeasonMap(t *testing.T) {
	groups := `{"results":[
		{"id":"season-split","name":"Season Split"},
		{"id":"tvdb-order","name":"TVDB Order"}
	]}`
	detail := `{"groups":[
		{"order":3,"episodes":[
			{"season_number":1,"episode_number":42},
			{"season_number":1,"episode_number":43}
		]},
		{"order":17,"episodes":[
			{"season_number":2,"episode_number":1},
			{"season_number":2,"episode_number":2}
		]},
		{"order":18,"episodes":[
			{"season_number":2,"episode_number":49},
			{"season_number":3,"episode_number":1}
		]},
		{"order":19,"episodes":[
			{"season_number":4,"episode_number":1},
			{"season_number":4,"episode_number":3}
		]}
	]}`
	srv := episodeGroupServer(t, groups, detail)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.AlternateSeasonMap(context.Background(), 30984)
	if err != nil {
		t.Fatalf("alternate season map: %v", err)
	}
	if mp := got[17]; mp.SeasonNumber != 2 || mp.EpisodeOffset != 0 {
		t.Errorf("season 17 -> %+v, want {2 0}", mp)
	}
	if mp := got[3]; mp.SeasonNumber != 1 || mp.EpisodeOffset != 41 {
		t.Errorf("season 3 -> %+v, want {1 41} (on-disk E01 is provider E42)", mp)
	}
	// A group straddling two provider seasons, and one that skips a number,
	// are both left out: a single season+offset would map part of them right
	// and quietly mis-title the rest, which is worse than reporting them.
	if mp, ok := got[18]; ok {
		t.Errorf("season 18 mapped to %+v; a group spanning two provider seasons must be skipped", mp)
	}
	if mp, ok := got[19]; ok {
		t.Errorf("season 19 mapped to %+v; a non-contiguous group must be skipped", mp)
	}
}

// TestTMDBAlternateSeasonMapNoTVDBGroup covers the common case: a show with
// episode groups, none of them TVDB's. Guessing from TMDB's type code would
// pick one of these re-cuts and write wrong metadata, so nothing is returned.
func TestTMDBAlternateSeasonMapNoTVDBGroup(t *testing.T) {
	groups := `{"results":[
		{"id":"netflix","name":"Netflix"},
		{"id":"arcs","name":"Story Arc"}
	]}`
	srv := episodeGroupServer(t, groups, `{"groups":[]}`)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.AlternateSeasonMap(context.Background(), 30984)
	if err != nil {
		t.Fatalf("alternate season map: %v", err)
	}
	if got != nil {
		t.Errorf("map = %v, want nil when the show publishes no TVDB order", got)
	}
}
