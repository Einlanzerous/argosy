package library

import (
	"context"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestBrowseStore(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run browse store tests")
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
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "br_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// Movie: scanned title overlaid by provider, then NFO override.
	var movieID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, sort_title, year, container, duration_seconds, file_path, tags, provider_metadata, metadata)
		 VALUES ($1,'movie','raw movie','raw movie',2008,'matroska',1380.5,$2,'{anime}',$3::jsonb,$4::jsonb) RETURNING id::text`,
		libID, "m-"+suffix+".mkv",
		`{"title":"Provider Movie","poster":"movies/9.jpg","overview":"prov ov"}`,
		`{"title":"NFO Movie"}`).Scan(&movieID); err != nil {
		t.Fatal(err)
	}

	// Series → season → episode.
	var seriesID, seasonID, epItemID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO series (library_id, title, sort_title, provider_metadata) VALUES ($1,'My Show','my show',$2::jsonb) RETURNING id::text`,
		libID, `{"title":"Provider Show"}`).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode','My Show S01E01',$2) RETURNING id::text`,
		libID, "ep-"+suffix+".mkv").Scan(&epItemID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,1,$2,'Pilot')`, seasonID, epItemID); err != nil {
		t.Fatal(err)
	}

	s := NewStore(pool, "/artwork")

	libs, err := s.ListLibraries(ctx, accID)
	if err != nil || len(libs) != 1 {
		t.Fatalf("libraries = %v (err %v), want 1", libs, err)
	}

	movies, err := s.ListMovies(ctx, accID, libID, 50, 0, "title", "")
	if err != nil {
		t.Fatal(err)
	}
	if movies.Total != 1 || len(movies.Items) != 1 {
		t.Fatalf("movies page = %+v, want 1", movies)
	}
	m := movies.Items[0]
	if m.Title != "NFO Movie" { // override wins over provider
		t.Errorf("movie title = %q, want NFO Movie", m.Title)
	}
	if m.PosterUrl == nil || *m.PosterUrl != "/artwork/movies/9.jpg" { // provider poster (no override poster)
		t.Errorf("movie poster = %v, want /artwork/movies/9.jpg", m.PosterUrl)
	}
	if m.Year == nil || *m.Year != 2008 {
		t.Errorf("movie year = %v, want 2008", m.Year)
	}
	if len(m.Tags) != 1 || m.Tags[0] != "anime" {
		t.Errorf("movie tags = %v, want [anime]", m.Tags)
	}

	// Tag filter: 'anime' matches the movie; an unknown tag matches nothing.
	if tagged, err := s.ListMovies(ctx, accID, libID, 50, 0, "title", "anime"); err != nil || tagged.Total != 1 {
		t.Fatalf("ListMovies tag=anime = %+v (err %v), want total 1", tagged, err)
	}
	if none, err := s.ListMovies(ctx, accID, libID, 50, 0, "title", "nope"); err != nil || none.Total != 0 {
		t.Fatalf("ListMovies tag=nope = %+v (err %v), want total 0", none, err)
	}

	series, err := s.ListSeries(ctx, accID, libID, 50, 0, "title", "")
	if err != nil || series.Total != 1 || series.Items[0].Title != "Provider Show" {
		t.Fatalf("series page = %+v (err %v), want 1 'Provider Show'", series, err)
	}

	detail, err := s.GetSeries(ctx, accID, "00000000-0000-0000-0000-000000000000", seriesID)
	if err != nil || detail == nil {
		t.Fatalf("series detail err %v", err)
	}
	if len(detail.Seasons) != 1 || len(detail.Seasons[0].Episodes) != 1 || detail.Seasons[0].Episodes[0].EpisodeNumber != 1 {
		t.Fatalf("series detail seasons = %+v, want 1 season / 1 episode", detail.Seasons)
	}

	item, err := s.GetItem(ctx, accID, movieID)
	if err != nil || item == nil {
		t.Fatalf("item detail err %v", err)
	}
	if item.Title != "NFO Movie" || item.Overview == nil || *item.Overview != "prov ov" {
		t.Errorf("item = title %q overview %v", item.Title, item.Overview)
	}
	if item.DurationSeconds == nil || *item.DurationSeconds < 1380 {
		t.Errorf("item duration = %v, want ~1380.5", item.DurationSeconds)
	}

	// Account isolation: another account can't see the item.
	var otherAcc string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "other_"+suffix).Scan(&otherAcc); err != nil {
		t.Fatal(err)
	}
	if got, err := s.GetItem(ctx, otherAcc, movieID); err != nil || got != nil {
		t.Fatalf("cross-account GetItem = %v (err %v), want nil", got, err)
	}
}
