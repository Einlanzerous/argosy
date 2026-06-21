package library

import (
	"context"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestVaultsStore(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run vault store tests")
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
	accID := one(`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "va_"+sfx)
	owner := one(`INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "owner_"+sfx)
	other := one(`INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "other_"+sfx)
	libID := one(`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`, accID, "lib_"+sfx, "/tmp/"+sfx)
	movieID := one(`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','The Film',$2) RETURNING id::text`, libID, "f"+sfx)
	seriesID := one(`INSERT INTO series (library_id, title) VALUES ($1,'The Show') RETURNING id::text`, libID)

	s := NewStore(pool, "/artwork")

	// Personal + shared vaults.
	v1, err := s.CreateVault(ctx, accID, owner, "Personal", nil, false)
	if err != nil || v1 == nil {
		t.Fatalf("create personal: %v", err)
	}
	v2, err := s.CreateVault(ctx, accID, owner, "Household", nil, true)
	if err != nil || v2 == nil {
		t.Fatalf("create shared: %v", err)
	}

	// Visibility: owner sees both; other sees only the shared one.
	if vs, _ := s.ListVaults(ctx, accID, owner); len(vs) != 2 {
		t.Fatalf("owner vaults = %d, want 2", len(vs))
	}
	otherVaults, _ := s.ListVaults(ctx, accID, other)
	if len(otherVaults) != 1 || otherVaults[0].Id != v2.Id || otherVaults[0].IsOwner {
		t.Fatalf("other vaults = %+v, want only the shared one (not owned)", otherVaults)
	}
	if d, _ := s.GetVault(ctx, accID, other, v1.Id.String()); d != nil {
		t.Error("a personal vault must not be visible to another profile")
	}

	// Add a film and a series; order follows insertion.
	mid, sid := movieID, seriesID
	if e, err := s.AddVaultItem(ctx, accID, v1.Id.String(), &mid, nil); err != nil || e == nil || string(e.Kind) != "movie" {
		t.Fatalf("add movie: entry=%+v err=%v", e, err)
	}
	if e, err := s.AddVaultItem(ctx, accID, v1.Id.String(), nil, &sid); err != nil || e == nil || string(e.Kind) != "series" {
		t.Fatalf("add series: entry=%+v err=%v", e, err)
	}
	d, _ := s.GetVault(ctx, accID, owner, v1.Id.String())
	if d == nil || len(d.Items) != 2 || d.Items[0].Title != "The Film" || d.Items[1].Title != "The Show" {
		t.Fatalf("vault items = %+v, want [The Film, The Show]", d)
	}

	// Re-adding the same film is a no-op (still 2 items).
	if _, err := s.AddVaultItem(ctx, accID, v1.Id.String(), &mid, nil); err != nil {
		t.Fatal(err)
	}
	if d, _ := s.GetVault(ctx, accID, owner, v1.Id.String()); len(d.Items) != 2 {
		t.Fatalf("after re-add, items = %d, want 2 (deduped)", len(d.Items))
	}

	// An item from another account can't be added.
	foreignAcc := one(`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "vaf_"+sfx)
	foreignLib := one(`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`, foreignAcc, "flib_"+sfx, "/tmp/f"+sfx)
	foreignMovie := one(`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Foreign',$2) RETURNING id::text`, foreignLib, "ff"+sfx)
	if e, err := s.AddVaultItem(ctx, accID, v1.Id.String(), &foreignMovie, nil); err != nil || e != nil {
		t.Errorf("cross-account add = %+v (err %v), want nil", e, err)
	}

	// Reorder: put the series first.
	d, _ = s.GetVault(ctx, accID, owner, v1.Id.String())
	movieEntry, seriesEntry := d.Items[0].EntryId.String(), d.Items[1].EntryId.String()
	if err := s.ReorderVault(ctx, v1.Id.String(), []string{seriesEntry, movieEntry}); err != nil {
		t.Fatal(err)
	}
	if d, _ := s.GetVault(ctx, accID, owner, v1.Id.String()); d.Items[0].Title != "The Show" {
		t.Errorf("after reorder, first = %q, want The Show", d.Items[0].Title)
	}

	// Remove the film.
	if removed, err := s.RemoveVaultItem(ctx, v1.Id.String(), movieEntry); err != nil || !removed {
		t.Fatalf("remove: removed=%v err=%v", removed, err)
	}
	if d, _ := s.GetVault(ctx, accID, owner, v1.Id.String()); len(d.Items) != 1 {
		t.Fatalf("after remove, items = %d, want 1", len(d.Items))
	}

	// Rename + share the personal vault; it becomes visible to the other profile.
	name := "Renamed"
	yes := true
	if v, err := s.UpdateVault(ctx, v1.Id.String(), owner, api.UpdateVaultRequest{Name: &name, Shared: &yes}); err != nil || v.Name != "Renamed" || !v.Shared {
		t.Fatalf("update = %+v err=%v", v, err)
	}
	if d, _ := s.GetVault(ctx, accID, other, v1.Id.String()); d == nil {
		t.Error("after sharing, the vault should be visible to the other profile")
	}

	// Meta reflects the new sharing; delete removes it.
	if m, _ := s.vaultMeta(ctx, v1.Id.String()); m == nil || m.ownerID != owner || !m.shared {
		t.Errorf("vaultMeta = %+v, want owner/shared", m)
	}
	if err := s.DeleteVault(ctx, v1.Id.String()); err != nil {
		t.Fatal(err)
	}
	if d, _ := s.GetVault(ctx, accID, owner, v1.Id.String()); d != nil {
		t.Error("vault should be gone after delete")
	}
}
