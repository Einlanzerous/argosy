package library

import (
	"context"
	"net/http/httptest"
	"os"
	"reflect"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestParseFilter(t *testing.T) {
	r := httptest.NewRequest("GET",
		"/?genre=Action&genre=Drama&rating_min=7.5&watched=unwatched&year_from=2000&year_to=2010", nil)
	got := parseFilter(r)
	want := browseFilter{
		Genres:    []string{"Action", "Drama"},
		RatingMin: 7.5,
		Watched:   "unwatched",
		YearFrom:  2000,
		YearTo:    2010,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("parseFilter = %+v, want %+v", got, want)
	}

	// An unrecognized watched value is dropped rather than passed through.
	if f := parseFilter(httptest.NewRequest("GET", "/?watched=bogus", nil)); f.Watched != "" {
		t.Errorf("watched=bogus -> %q, want empty", f.Watched)
	}
	// Empty query yields the zero filter (no constraints).
	if f := parseFilter(httptest.NewRequest("GET", "/", nil)); !reflect.DeepEqual(f, browseFilter{}) {
		t.Errorf("empty query -> %+v, want zero", f)
	}
}

func TestBrowseFilters(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run filter store tests")
	}
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, userID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "fi_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "u_"+suffix).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	movie := func(title string, year int, prov string) string {
		t.Helper()
		var id string
		if err := pool.QueryRow(ctx,
			`INSERT INTO media_items (library_id, kind, title, sort_title, year, file_path, provider_metadata)
			 VALUES ($1,'movie',$2,$2,$3,$4,$5::jsonb) RETURNING id::text`,
			libID, title, year, title+suffix+".mkv", prov).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	alpha := movie("Alpha", 2000, `{"genres":["Action","Drama"],"vote_average":8.0,"vote_count":100}`)
	beta := movie("Beta", 2010, `{"genres":["Comedy"],"vote_average":5.0,"vote_count":50}`)
	movie("Gamma", 2020, `{}`) // no genres, no rating

	// Watched state: Alpha finished, Beta in progress, Gamma untouched.
	if _, err := pool.Exec(ctx, `INSERT INTO play_state (user_id, media_item_id, position_seconds, watched) VALUES ($1,$2,0,true)`, userID, alpha); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO play_state (user_id, media_item_id, position_seconds, watched) VALUES ($1,$2,120,false)`, userID, beta); err != nil {
		t.Fatal(err)
	}

	// Series with two episodes: one watched, one not → in progress overall.
	var seriesID, seasonID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title, provider_metadata) VALUES ($1,'Show','show',$2::jsonb) RETURNING id::text`,
		libID, `{"genres":["Drama"],"vote_average":7.0,"vote_count":10}`).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	for i := 1; i <= 2; i++ {
		var epItem string
		if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
			libID, "Show E"+strconv.Itoa(i), "show-"+strconv.Itoa(i)+suffix+".mkv").Scan(&epItem); err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id) VALUES ($1,$2,$3)`, seasonID, i, epItem); err != nil {
			t.Fatal(err)
		}
		if i == 1 { // first episode watched, second untouched
			if _, err := pool.Exec(ctx, `INSERT INTO play_state (user_id, media_item_id, watched) VALUES ($1,$2,true)`, userID, epItem); err != nil {
				t.Fatal(err)
			}
		}
	}

	s := NewStore(pool, "/artwork")

	movieTitles := func(sort string, f browseFilter) []string {
		t.Helper()
		page, err := s.ListMovies(ctx, accID, libID, userID, 50, 0, sort, f)
		if err != nil {
			t.Fatalf("ListMovies(%+v): %v", f, err)
		}
		out := make([]string, 0, len(page.Items))
		for _, m := range page.Items {
			out = append(out, m.Title)
		}
		return out
	}
	eq := func(got, want []string, ctx string) {
		t.Helper()
		if len(got) != len(want) {
			t.Fatalf("%s = %v, want %v", ctx, got, want)
			return
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("%s = %v, want %v", ctx, got, want)
			}
		}
	}

	// Genre: any-of overlap, effective (provider) genres.
	eq(movieTitles("title", browseFilter{Genres: []string{"Action"}}), []string{"Alpha"}, "genre=Action")
	eq(movieTitles("title", browseFilter{Genres: []string{"Comedy", "Drama"}}), []string{"Alpha", "Beta"}, "genre=Comedy,Drama")
	// Rating floor excludes the lower-rated and the unrated.
	eq(movieTitles("title", browseFilter{RatingMin: 6}), []string{"Alpha"}, "rating_min=6")
	// Year range.
	eq(movieTitles("title", browseFilter{YearFrom: 2005, YearTo: 2015}), []string{"Beta"}, "year 2005-2015")
	// Sort by rating: highest first, unrated last.
	eq(movieTitles("rating", browseFilter{}), []string{"Alpha", "Beta", "Gamma"}, "sort=rating")
	// Per-user watched state.
	eq(movieTitles("title", browseFilter{Watched: "watched"}), []string{"Alpha"}, "watched")
	eq(movieTitles("title", browseFilter{Watched: "unwatched"}), []string{"Gamma"}, "unwatched")
	eq(movieTitles("title", browseFilter{Watched: "in_progress"}), []string{"Beta"}, "in_progress")
	// Composability: rating floor never excludes a clearly-rated item, but combined
	// with a non-matching genre yields nothing.
	eq(movieTitles("title", browseFilter{Genres: []string{"Action"}, RatingMin: 9}), []string{}, "genre+rating compose")

	// Rating field is surfaced on the summary.
	if got := movieTitles("title", browseFilter{Genres: []string{"Action"}}); len(got) == 1 {
		page, _ := s.ListMovies(ctx, accID, libID, userID, 50, 0, "title", browseFilter{Genres: []string{"Action"}})
		if page.Items[0].Rating == nil || *page.Items[0].Rating != 8 {
			t.Errorf("Alpha rating = %v, want 8", page.Items[0].Rating)
		}
	}

	// Series watched-state aggregates over episodes (one of two watched → in progress).
	seriesTitles := func(f browseFilter) []string {
		t.Helper()
		page, err := s.ListSeries(ctx, accID, libID, userID, 50, 0, "title", f)
		if err != nil {
			t.Fatalf("ListSeries(%+v): %v", f, err)
		}
		out := make([]string, 0, len(page.Items))
		for _, r := range page.Items {
			out = append(out, r.Title)
		}
		return out
	}
	eq(seriesTitles(browseFilter{Watched: "in_progress"}), []string{"Show"}, "series in_progress")
	eq(seriesTitles(browseFilter{Watched: "watched"}), []string{}, "series watched")
	eq(seriesTitles(browseFilter{Watched: "unwatched"}), []string{}, "series unwatched")
	eq(seriesTitles(browseFilter{Genres: []string{"Drama"}}), []string{"Show"}, "series genre")
	eq(seriesTitles(browseFilter{RatingMin: 6}), []string{"Show"}, "series rating_min")
}
