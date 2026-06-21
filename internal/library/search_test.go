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

func TestSearchTSQuery(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", ""},
		{"   ", ""},
		{"blade", "blade:*"},
		{"your na", "your:* & na:*"},
		{"  Blade   Runner ", "blade:* & runner:*"},
		{"sci-fi", "sci:* & fi:*"},                              // punctuation splits into tokens
		{"!!!", ""},                                             // all-symbol input is dropped
		{"to_tsquery('x') | y", "to:* & tsquery:* & x:* & y:*"}, // operators are stripped, no injection
		{"君の名は", "君の名は:*"},                                      // non-Latin letters preserved
	}
	for _, c := range cases {
		if got := searchTSQuery(c.in); got != c.want {
			t.Errorf("searchTSQuery(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestSearchStore(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run search store tests")
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
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "se_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	addMovie := func(title, filePath, tags, prov, over string) {
		t.Helper()
		if _, err := pool.Exec(ctx,
			`INSERT INTO media_items (library_id, kind, title, sort_title, file_path, tags, provider_metadata, metadata)
			 VALUES ($1,'movie',$2,$2,$3,$4,$5::jsonb,$6::jsonb)`,
			libID, title, filePath, tags, prov, over); err != nil {
			t.Fatal(err)
		}
	}
	// base title "raw blade", override title "Blade Runner", anime tag, Sci-Fi genre,
	// overview mentions "replicant".
	addMovie("raw blade", "br.mkv", "{anime}",
		`{"genres":["Sci-Fi"],"overview":"a blade runner hunts a replicant"}`,
		`{"title":"Blade Runner"}`)
	addMovie("Big Buck Bunny", "bbb.mkv", "{}", `{}`, `{}`)
	// Ranking probe: "zen" in a title (weight A) must outrank "zen" only in an overview (weight C).
	addMovie("Zen Garden", "zg.mkv", "{}", `{}`, `{}`)
	addMovie("Quiet Place", "qp.mkv", "{}", `{"overview":"a peaceful zen retreat"}`, `{}`)

	var seriesID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Breaking Bad','breaking bad') RETURNING id::text`,
		libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}

	s := NewStore(pool, "/artwork")

	titlesOf := func(q string) []string {
		t.Helper()
		res, err := s.Search(ctx, accID, q, 8)
		if err != nil {
			t.Fatalf("Search(%q): %v", q, err)
		}
		var out []string
		for _, m := range res.Movies {
			out = append(out, m.Title)
		}
		return out
	}
	contains := func(xs []string, want string) bool {
		for _, x := range xs {
			if x == want {
				return true
			}
		}
		return false
	}

	// Title prefix (against the override title) matches; an unrelated film does not.
	if got := titlesOf("blade"); !contains(got, "Blade Runner") || contains(got, "Big Buck Bunny") {
		t.Errorf(`Search("blade") movies = %v, want Blade Runner only`, got)
	}
	// Tag, genre, and overview are all searchable and resolve to the same film.
	for _, q := range []string{"anime", "sci", "replicant"} {
		if got := titlesOf(q); !contains(got, "Blade Runner") {
			t.Errorf(`Search(%q) movies = %v, want to include Blade Runner`, q, got)
		}
	}
	// Two-token AND narrows.
	if got := titlesOf("big bunny"); !contains(got, "Big Buck Bunny") {
		t.Errorf(`Search("big bunny") = %v, want Big Buck Bunny`, got)
	}
	// Ranking: title hit outranks overview-only hit.
	if got := titlesOf("zen"); len(got) < 2 || got[0] != "Zen Garden" {
		t.Errorf(`Search("zen") = %v, want "Zen Garden" ranked first`, got)
	}
	// Series are grouped separately from films.
	res, err := s.Search(ctx, accID, "breaking", 8)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Series) != 1 || res.Series[0].Title != "Breaking Bad" || len(res.Movies) != 0 {
		t.Errorf(`Search("breaking") = movies %v / series %v, want 0 films / [Breaking Bad]`, res.Movies, res.Series)
	}
	// Empty query yields empty, non-nil groups (never errors).
	if res, err := s.Search(ctx, accID, "   ", 8); err != nil || len(res.Movies) != 0 || len(res.Series) != 0 {
		t.Errorf("Search(blank) = %+v (err %v), want empty groups", res, err)
	}
	// Account isolation: another account sees nothing.
	var other string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "seo_"+suffix).Scan(&other); err != nil {
		t.Fatal(err)
	}
	if res, err := s.Search(ctx, other, "blade", 8); err != nil || len(res.Movies) != 0 {
		t.Errorf("cross-account Search = %+v (err %v), want empty", res, err)
	}
}
