package stevedore

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestParseMovieNFO(t *testing.T) {
	o, err := parseMovieNFO([]byte(`<movie><title>The Real Title</title><plot>A great plot.</plot><year>1999</year><genre>Action</genre><genre>Sci-Fi</genre></movie>`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if o["title"] != "The Real Title" || o["overview"] != "A great plot." || o["year"] != 1999 {
		t.Fatalf("override = %v", o)
	}
	if g, ok := o["genres"].([]string); !ok || len(g) != 2 {
		t.Fatalf("genres = %v", o["genres"])
	}
}

func TestParseEpisodeNFO(t *testing.T) {
	o, err := parseEpisodeNFO([]byte(`<episodedetails><title>Pilot</title><plot>ep plot</plot></episodedetails>`))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if o["title"] != "Pilot" || o["overview"] != "ep plot" {
		t.Fatalf("override = %v", o)
	}
}

func TestApplyOverridesDB(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run override DB tests")
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
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ovr_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	moviePath := "Big Buck Bunny (2008).mkv"
	if _, err := pool.Exec(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Big Buck Bunny (2008)',$2)`,
		libID, moviePath); err != nil {
		t.Fatal(err)
	}

	src := &fakeSource{files: map[string][]byte{
		moviePath:                   []byte("video"),
		"Big Buck Bunny (2008).nfo": []byte(`<movie><title>Big Buck Bunny</title><plot>Override plot</plot><year>2008</year></movie>`),
		"poster.jpg":                []byte("imgbytes"),
	}}

	sc := NewScanner(pool, slog.New(slog.NewTextHandler(io.Discard, nil)), t.TempDir())
	if err := sc.ApplyOverrides(ctx, libID, src); err != nil {
		t.Fatalf("apply overrides: %v", err)
	}

	var raw []byte
	if err := pool.QueryRow(ctx, `SELECT metadata FROM media_items WHERE library_id=$1 AND kind='movie'`, libID).Scan(&raw); err != nil {
		t.Fatal(err)
	}
	var meta map[string]any
	if err := json.Unmarshal(raw, &meta); err != nil {
		t.Fatal(err)
	}
	if meta["title"] != "Big Buck Bunny" || meta["overview"] != "Override plot" {
		t.Fatalf("override metadata = %v", meta)
	}
	if p, ok := meta["poster"].(string); !ok || p == "" {
		t.Fatalf("expected local poster override, got %v", meta["poster"])
	}
}
