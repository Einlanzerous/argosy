package stevedore

import (
	"context"
	"io"
	"log/slog"
	"os"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestParseEpisode(t *testing.T) {
	cases := []struct {
		path     string
		show     string
		season   int
		episodes []int
		ok       bool
	}{
		{"Show Name/Season 1/Show Name S01E02 Title.mkv", "Show Name", 1, []int{2}, true},
		{"shows/Sword Art Online/Season 1/Sword Art Online S01E01.mkv", "Sword Art Online", 1, []int{1}, true}, // category dir skipped
		{"anime/Cowboy Bebop/Season 1/Cowboy Bebop S01E02.mkv", "Cowboy Bebop", 1, []int{2}, true},
		{"Show.Name.S03E10.1080p.mkv", "Show Name", 3, []int{10}, true}, // resolution tag not a range end
		{"Show Name/Show Name 1x05.mkv", "Show Name", 1, []int{5}, true},
		{"Specials/Show Name S00E01.mkv", "Show Name", 0, []int{1}, true},
		// Combined rips: one file backing several episodes.
		{"The Good Place/Season 1/The Good Place S01E01-E02.mkv", "The Good Place", 1, []int{1, 2}, true},
		{"The Office/Season 2/The Office S02E01E02.mkv", "The Office", 2, []int{1, 2}, true},
		{"Show Name/Season 1/Show Name S01E01-E03.mkv", "Show Name", 1, []int{1, 2, 3}, true},
		{"Show Name/Show Name 1x01-02.mkv", "Show Name", 1, []int{1, 2}, true},
		{"Show Name/Season 1/Show Name S01E04-03.mkv", "Show Name", 1, []int{4}, true}, // non-increasing → single
		{"Movies/Random Movie (2020).mkv", "", 0, nil, false},
	}
	for _, c := range cases {
		info, ok := parseEpisode(c.path)
		if ok != c.ok {
			t.Errorf("%q: ok=%v, want %v", c.path, ok, c.ok)
			continue
		}
		if !ok {
			continue
		}
		if info.show != c.show || info.season != c.season || !slices.Equal(info.episodes, c.episodes) {
			t.Errorf("%q: got {%q s%d e%v}, want {%q s%d e%v}",
				c.path, info.show, info.season, info.episodes, c.show, c.season, c.episodes)
		}
	}
}

func TestParseMovie(t *testing.T) {
	title, year := parseMovie("Big Buck Bunny (2008)")
	if title != "Big Buck Bunny" || year == nil || *year != 2008 {
		t.Errorf("got (%q, %v), want (Big Buck Bunny, 2008)", title, year)
	}
	title, year = parseMovie("No Year Movie")
	if title != "No Year Movie" || year != nil {
		t.Errorf("got (%q, %v), want (No Year Movie, nil)", title, year)
	}
}

func TestClassifyDB(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run classify DB tests")
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
	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "cls_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	insert := func(kind, filePath, title string) {
		if _, err := pool.Exec(ctx,
			`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,$2,$3,$4)`,
			libID, kind, title, filePath); err != nil {
			t.Fatal(err)
		}
	}
	insert("episode", "My Show/Season 1/My Show S01E01.mkv", "My Show S01E01")
	insert("episode", "My Show/Season 1/My Show S01E02.mkv", "My Show S01E02")
	insert("movie", "Big Buck Bunny (2008).mkv", "Big Buck Bunny (2008)")
	insert("episode", "Extras/loose clip.mkv", "loose clip") // unparseable
	// An anime series episode: Classify should tag the parent series 'anime'.
	insert("episode", "anime/Cowboy Bebop/Season 1/Cowboy Bebop S01E01.mkv", "Cowboy Bebop S01E01")

	sc := NewScanner(pool, slog.New(slog.NewTextHandler(io.Discard, nil)), "")
	if err := sc.Classify(ctx, libID); err != nil {
		t.Fatalf("classify: %v", err)
	}

	queryInt := func(q string) int {
		t.Helper()
		var n int
		if err := pool.QueryRow(ctx, q, libID).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	series := queryInt(`SELECT count(*) FROM series WHERE library_id=$1`)
	seasons := queryInt(`SELECT count(*) FROM seasons s JOIN series r ON r.id=s.series_id WHERE r.library_id=$1`)
	episodes := queryInt(`SELECT count(*) FROM episodes e JOIN seasons s ON s.id=e.season_id JOIN series r ON r.id=s.series_id WHERE r.library_id=$1`)
	linked := queryInt(`SELECT count(*) FROM episodes e JOIN seasons s ON s.id=e.season_id JOIN series r ON r.id=s.series_id WHERE r.library_id=$1 AND e.media_item_id IS NOT NULL`)
	if series != 2 || seasons != 2 || episodes != 3 || linked != 3 {
		t.Fatalf("hierarchy series=%d seasons=%d episodes=%d linked=%d, want 2/2/3/3", series, seasons, episodes, linked)
	}

	// The anime series picked up its 'anime' tag from the episode path; the
	// non-anime series did not.
	if n := queryInt(`SELECT count(*) FROM series WHERE library_id=$1 AND 'anime' = ANY(tags)`); n != 1 {
		t.Fatalf("series tagged anime = %d, want 1 (Cowboy Bebop only)", n)
	}

	var movieYear *int
	if err := pool.QueryRow(ctx, `SELECT year FROM media_items WHERE library_id=$1 AND kind='movie'`, libID).Scan(&movieYear); err != nil {
		t.Fatal(err)
	}
	if movieYear == nil || *movieYear != 2008 {
		t.Fatalf("movie year = %v, want 2008", movieYear)
	}

	if review := queryInt(`SELECT count(*) FROM media_items WHERE library_id=$1 AND review_required`); review != 1 {
		t.Fatalf("review_required count = %d, want 1 (the loose clip)", review)
	}
}
