package stevedore

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

// TestStoreOmitsUnknownYear pins ARGY-309: a match with no release date must not
// persist year 0 into provider_metadata (clients rendered it as "0"), and must
// leave the year column NULL.
func TestStoreOmitsUnknownYear(t *testing.T) {
	dsn := testdb.DSN(t)
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
	var accID, libID, seriesID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "yr_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Undated','undated') RETURNING id::text`, libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}

	m := NewMatcher(pool, fakeProvider{}, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	m.download = func(context.Context, string, string) error { return nil }
	if err := m.store(ctx, "series", "series", seriesID, &metadata.Match{TMDBID: 333, Title: "Undated", Year: 0}); err != nil {
		t.Fatalf("store: %v", err)
	}

	var pm []byte
	var year *int
	if err := pool.QueryRow(ctx, `SELECT provider_metadata, year FROM series WHERE id=$1`, seriesID).Scan(&pm, &year); err != nil {
		t.Fatal(err)
	}
	var meta map[string]any
	if err := json.Unmarshal(pm, &meta); err != nil {
		t.Fatal(err)
	}
	if v, present := meta["year"]; present {
		t.Errorf("provider_metadata.year = %v, want absent", v)
	}
	if year != nil {
		t.Errorf("year column = %d, want NULL", *year)
	}
}
