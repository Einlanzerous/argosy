package metadata

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
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

// episodeGroupServer serves the two documents SeriesEpisodeGroup reads, shaped
// like TMDB's real answer: a "TVDB Order" group whose entries are the seasons
// Sonarr laid the files out under.
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
			{"season_number":0,"name":"Specials"},
			{"season_number":1,"name":"Bleach"},
			{"season_number":2,"name":"Thousand-Year Blood War"}
		]}`))
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.SeriesSeasons(context.Background(), 30984)
	if err != nil {
		t.Fatalf("series seasons: %v", err)
	}
	if len(got) != 3 || got[2].Number != 2 || got[2].Name != "Thousand-Year Blood War" {
		t.Fatalf("seasons = %+v", got)
	}
	// Nothing numbered 17 — which is why season 17 on disk went empty.
	for _, s := range got {
		if s.Number == 17 {
			t.Fatal("provider reported a season 17; the fixture is wrong")
		}
	}
}

// TestTMDBSeriesEpisodeGroup pins ARGY-224's translation. The episodes come back
// renumbered onto the library's numbering, so a group drawing from several
// provider seasons — which a season+offset mapping cannot express, and which is
// the majority of One Piece — needs no special handling at all.
func TestTMDBSeriesEpisodeGroup(t *testing.T) {
	groups := `{"results":[
		{"id":"season-split","name":"Season Split"},
		{"id":"tvdb-order","name":"TVDB Order"}
	]}`
	detail := `{"groups":[
		{"order":17,"name":"Bleach: Thousand-Year Blood War","episodes":[
			{"order":0,"name":"The Blood Warfare","overview":"ov1","still_path":"/e1.jpg","vote_average":8.1,"vote_count":60,"season_number":2,"episode_number":1},
			{"order":1,"name":"Foundation Stones","overview":"ov2","still_path":"","season_number":2,"episode_number":2}
		]},
		{"order":11,"name":"Season 11 - Water 7 & Enies Lobby","episodes":[
			{"order":0,"name":"Straddle A","overview":"a","season_number":7,"episode_number":227},
			{"order":1,"name":"Straddle B","overview":"b","season_number":8,"episode_number":229}
		]},
		{"order":9,"name":"Specials","episodes":[
			{"order":0,"name":"A Special","season_number":0,"episode_number":1}
		]}
	]}`
	srv := episodeGroupServer(t, groups, detail)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL, ImageBaseURL: "https://img"})
	got, err := tm.SeriesEpisodeGroup(context.Background(), 30984)
	if err != nil {
		t.Fatalf("episode group: %v", err)
	}

	s17 := got[17]
	if len(s17) != 2 {
		t.Fatalf("season 17 = %+v, want 2 episodes", s17)
	}
	// Numbered as the files on disk are, not as TMDB numbers them.
	if s17[0].Number != 1 || s17[0].Name != "The Blood Warfare" || s17[0].StillURL != "https://img/w300/e1.jpg" {
		t.Errorf("S17E01 = %+v", s17[0])
	}
	if s17[0].VoteAverage != 8.1 || s17[0].VoteCount != 60 {
		t.Errorf("S17E01 rating = %v/%v, want 8.1/60", s17[0].VoteAverage, s17[0].VoteCount)
	}
	if s17[1].Number != 2 || s17[1].StillURL != "" {
		t.Errorf("S17E02 = %+v", s17[1])
	}

	// A group drawing from two provider seasons is kept whole — this is the
	// case the old season+offset mapping had to drop, taking 62% of One Piece
	// with it.
	s11 := got[11]
	if len(s11) != 2 || s11[0].Number != 1 || s11[1].Number != 2 || s11[1].Name != "Straddle B" {
		t.Errorf("season 11 = %+v, want both episodes renumbered 1,2", s11)
	}

	// A group named "Specials" is season 0 regardless of its display position.
	if _, ok := got[9]; ok {
		t.Errorf("group named Specials was keyed on its order (9) rather than 0: %v", got)
	}
	if len(got[0]) != 1 {
		t.Errorf("season 0 = %+v, want the Specials group", got[0])
	}
}

// TestTMDBGroupNameBeatsOrder covers the curator-editable display position: the
// group's `order` is not authoritative, so where the name states the season the
// name wins. A silently shifted position would otherwise move every season's
// metadata by one, and the shifted groups would still look internally consistent.
func TestTMDBGroupNameBeatsOrder(t *testing.T) {
	groups := `{"results":[{"id":"tvdb-order","name":"TVDB Order"}]}`
	detail := `{"groups":[
		{"order":4,"name":"Season 5 - Reverse Mountain","episodes":[
			{"order":0,"name":"Ep","season_number":1,"episode_number":61}
		]}
	]}`
	srv := episodeGroupServer(t, groups, detail)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.SeriesEpisodeGroup(context.Background(), 30984)
	if err != nil {
		t.Fatalf("episode group: %v", err)
	}
	if _, ok := got[4]; ok {
		t.Errorf("group keyed on order 4 despite its name saying season 5: %v", got)
	}
	if len(got[5]) != 1 {
		t.Errorf("got = %v, want the group keyed on season 5", got)
	}
}

// TestTVDBGroupScore pins which of a show's several TVDB-ish groups is the one
// Sonarr's folders came in. An absolute or DVD ordering renumbers the episodes
// differently, so picking whichever the API listed first would mis-title
// everything.
func TestTVDBGroupScore(t *testing.T) {
	cases := map[string]bool{
		"TVDB Order":          true,
		"tvdb order":          true,
		"TVDB":                true,
		"TVDB Absolute Order": false,
		"TVDB DVD Order":      false,
		"TVDB Digital Order":  false,
		"Story Arc":           false,
		"Netflix":             false,
	}
	for name, want := range cases {
		if got := tvdbGroupScore(name) > 0; got != want {
			t.Errorf("tvdbGroupScore(%q) candidate = %v, want %v", name, got, want)
		}
	}
	if tvdbGroupScore("TVDB Order") <= tvdbGroupScore("TVDB") {
		t.Error("an exact \"TVDB Order\" must outrank a looser TVDB match")
	}
}

// TestTMDBEpisodeGroupPrefersExactOrder is the same point end to end: the
// alternate orderings are listed first, and must not win.
func TestTMDBEpisodeGroupPrefersExactOrder(t *testing.T) {
	groups := `{"results":[
		{"id":"absolute","name":"TVDB Absolute Order"},
		{"id":"dvd","name":"TVDB DVD Order"},
		{"id":"tvdb-order","name":"TVDB Order"}
	]}`
	detail := `{"groups":[{"order":3,"name":"Arc","episodes":[
		{"order":0,"name":"Right One","season_number":1,"episode_number":42}
	]}]}`
	srv := episodeGroupServer(t, groups, detail)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.SeriesEpisodeGroup(context.Background(), 30984)
	if err != nil {
		t.Fatalf("episode group: %v", err)
	}
	if len(got[3]) != 1 || got[3][0].Name != "Right One" {
		t.Errorf("got = %v, want the exact \"TVDB Order\" group", got)
	}
}

// TestTMDBEpisodeGroupNoTVDBGroup covers the common case: a show with episode
// groups, none of them TVDB's. Guessing from TMDB's type code would pick one of
// these re-cuts and write wrong metadata, so nothing is returned.
func TestTMDBEpisodeGroupNoTVDBGroup(t *testing.T) {
	groups := `{"results":[
		{"id":"netflix","name":"Netflix"},
		{"id":"arcs","name":"Story Arc"}
	]}`
	srv := episodeGroupServer(t, groups, `{"groups":[]}`)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.SeriesEpisodeGroup(context.Background(), 30984)
	if err != nil {
		t.Fatalf("episode group: %v", err)
	}
	if got != nil {
		t.Errorf("map = %v, want nil when the show publishes no TVDB ordering", got)
	}
}

// TestTMDBPermanentError separates an outage from an answer. A series whose
// tmdb_id was merged away 404s on every sweep forever, and treating that as
// transient hides it behind a warning nobody reads.
func TestTMDBPermanentError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	_, err := tm.SeriesSeasons(context.Background(), 30984)
	if err == nil {
		t.Fatal("expected an error")
	}
	if !IsPermanent(err) {
		t.Errorf("IsPermanent(%v) = false, want true for a 404", err)
	}

	srv2 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer srv2.Close()
	tm2 := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv2.URL})
	tm2.retries, tm2.baseBackoff = 0, time.Millisecond
	_, err = tm2.SeriesSeasons(context.Background(), 30984)
	if err == nil {
		t.Fatal("expected an error")
	}
	if IsPermanent(err) {
		t.Errorf("IsPermanent(%v) = true, want false for a 502 — that one retries", err)
	}
}

// TestTMDBEpisodeGroupDuplicateSeason covers a malformed ordering: two groups
// resolving to the same season. Keeping either would be a coin flip over which
// arc's titles a season gets, so both are dropped and the season is left to be
// reported as unmapped instead.
func TestTMDBEpisodeGroupDuplicateSeason(t *testing.T) {
	groups := `{"results":[{"id":"tvdb-order","name":"TVDB Order"}]}`
	// Two groups whose names both claim season 3, plus a well-formed season 4
	// that must survive alongside them.
	detail := `{"groups":[
		{"order":3,"name":"Season 3 - First Claim","episodes":[
			{"order":0,"name":"first","season_number":1,"episode_number":10}
		]},
		{"order":7,"name":"Season 3 - Second Claim","episodes":[
			{"order":0,"name":"second","season_number":1,"episode_number":20}
		]},
		{"order":4,"name":"Season 4","episodes":[
			{"order":0,"name":"fine","season_number":1,"episode_number":30}
		]}
	]}`
	srv := episodeGroupServer(t, groups, detail)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.SeriesEpisodeGroup(context.Background(), 30984)
	if err != nil {
		t.Fatalf("episode group: %v", err)
	}
	if eps, ok := got[3]; ok {
		t.Errorf("season 3 = %+v; a season claimed twice must be dropped, not guessed", eps)
	}
	if len(got[4]) != 1 || got[4][0].Name != "fine" {
		t.Errorf("season 4 = %+v; one bad season must not discard the rest", got[4])
	}
}

// TestTMDBEpisodeGroupAllDropped: if nothing survives, the show must read as
// "publishes no ordering" rather than as an empty-but-present one, so the
// resolver falls through to the provider's own numbering.
func TestTMDBEpisodeGroupAllDropped(t *testing.T) {
	groups := `{"results":[{"id":"tvdb-order","name":"TVDB Order"}]}`
	detail := `{"groups":[
		{"order":1,"name":"Season 2 - A","episodes":[{"order":0,"name":"a","season_number":1,"episode_number":1}]},
		{"order":9,"name":"Season 2 - B","episodes":[{"order":0,"name":"b","season_number":1,"episode_number":2}]}
	]}`
	srv := episodeGroupServer(t, groups, detail)
	defer srv.Close()

	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL})
	got, err := tm.SeriesEpisodeGroup(context.Background(), 30984)
	if err != nil {
		t.Fatalf("episode group: %v", err)
	}
	if got != nil {
		t.Errorf("got = %v, want nil so the caller treats it as no ordering at all", got)
	}
}
