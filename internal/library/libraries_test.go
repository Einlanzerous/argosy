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

func TestLibraryManagement(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run library management tests")
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
	var accID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "lm_"+sfx).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	s := NewStore(pool, "/artwork")

	lib, err := s.CreateLibrary(ctx, accID, "Films", "/srv/media/films", "movie")
	if err != nil || lib.RootPath == nil || *lib.RootPath != "/srv/media/films" || lib.Kind != "movie" {
		t.Fatalf("create = %+v err=%v", lib, err)
	}

	libs, err := s.ListLibraries(ctx, accID)
	if err != nil || len(libs) != 1 || libs[0].RootPath == nil || *libs[0].RootPath != "/srv/media/films" {
		t.Fatalf("list = %+v err=%v, want one with rootPath", libs, err)
	}

	// Delete reports success once, then the row is gone.
	if removed, err := s.DeleteLibrary(ctx, accID, lib.Id.String()); err != nil || !removed {
		t.Fatalf("delete = %v err=%v, want removed", removed, err)
	}
	if removed, _ := s.DeleteLibrary(ctx, accID, lib.Id.String()); removed {
		t.Error("second delete reported removed, want false")
	}
	if libs, _ := s.ListLibraries(ctx, accID); len(libs) != 0 {
		t.Errorf("after delete, libraries = %d, want 0", len(libs))
	}

	// A library is scoped to its account: another account can't delete it.
	keep, _ := s.CreateLibrary(ctx, accID, "Keep", "/srv/media/keep", "mixed")
	var otherAcc string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "lmo_"+sfx).Scan(&otherAcc); err != nil {
		t.Fatal(err)
	}
	if removed, _ := s.DeleteLibrary(ctx, otherAcc, keep.Id.String()); removed {
		t.Error("cross-account delete succeeded, want refused")
	}
}
