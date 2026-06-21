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

func TestUserLabels(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run label store tests")
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

	sfx := strconv.FormatInt(time.Now().UnixNano(), 36)
	one := func(q string, args ...any) string {
		t.Helper()
		var id string
		if err := pool.QueryRow(ctx, q, args...).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	accID := one(`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ul_"+sfx)
	me := one(`INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "me_"+sfx)
	other := one(`INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "ot_"+sfx)
	libID := one(`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`, accID, "lib_"+sfx, "/tmp/"+sfx)
	movieID := one(`INSERT INTO media_items (library_id, kind, title, sort_title, file_path) VALUES ($1,'movie','Film','film',$2) RETURNING id::text`, libID, "f"+sfx)
	seriesID := one(`INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Show','show') RETURNING id::text`, libID)

	s := NewStore(pool, "/artwork")

	// Add labels to a film and a series; re-add is a no-op.
	if labels, found, err := s.AddItemLabel(ctx, accID, me, movieID, "Favorite"); err != nil || !found || len(labels) != 1 {
		t.Fatalf("add item label = %v found=%v err=%v", labels, found, err)
	}
	if labels, _, _ := s.AddItemLabel(ctx, accID, me, movieID, "Rewatch"); len(labels) != 2 {
		t.Fatalf("after 2nd label = %v, want 2", labels)
	}
	if labels, _, _ := s.AddItemLabel(ctx, accID, me, movieID, "Favorite"); len(labels) != 2 {
		t.Errorf("re-add dup = %v, want still 2", labels)
	}
	if _, found, _ := s.AddSeriesLabel(ctx, accID, me, seriesID, "Favorite"); !found {
		t.Fatal("add series label not found")
	}

	// A film outside the account can't be labelled.
	otherAcc := one(`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ulo_"+sfx)
	otherLib := one(`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`, otherAcc, "olib_"+sfx, "/tmp/o"+sfx)
	foreign := one(`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','F',$2) RETURNING id::text`, otherLib, "ff"+sfx)
	if _, found, _ := s.AddItemLabel(ctx, accID, me, foreign, "Nope"); found {
		t.Error("labelling a cross-account item should report not-found")
	}

	// Labels are per-user: 'other' sees none of mine; my distinct list is sorted.
	if ls, _ := s.ItemLabels(ctx, other, movieID); len(ls) != 0 {
		t.Errorf("other's item labels = %v, want none", ls)
	}
	if ls, _ := s.ListLabels(ctx, me); len(ls) != 2 || ls[0] != "Favorite" || ls[1] != "Rewatch" {
		t.Errorf("my labels = %v, want [Favorite, Rewatch]", ls)
	}

	// Filter: my "Rewatch" label matches the film; 'other' matches nothing.
	if p, err := s.ListMovies(ctx, accID, libID, me, 50, 0, "title", browseFilter{Label: "Rewatch"}); err != nil || p.Total != 1 {
		t.Fatalf("label filter (me) = %+v err=%v, want 1", p, err)
	}
	if p, _ := s.ListMovies(ctx, accID, libID, other, 50, 0, "title", browseFilter{Label: "Rewatch"}); p.Total != 0 {
		t.Errorf("label filter (other) = %d, want 0 (per-user)", p.Total)
	}
	// Series label filter.
	if p, _ := s.ListSeries(ctx, accID, libID, me, 50, 0, "title", browseFilter{Label: "Favorite"}); p.Total != 1 {
		t.Errorf("series label filter = %d, want 1", p.Total)
	}

	// Remove drops it from the list and the filter.
	if err := s.RemoveItemLabel(ctx, me, movieID, "Rewatch"); err != nil {
		t.Fatal(err)
	}
	if ls, _ := s.ItemLabels(ctx, me, movieID); len(ls) != 1 || ls[0] != "Favorite" {
		t.Errorf("after remove = %v, want [Favorite]", ls)
	}
}
