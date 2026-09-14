package library

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/fileid"
	"github.com/Einlanzerous/argosy/internal/stow"
	"github.com/Einlanzerous/argosy/internal/subtitle"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func identityPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
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
	return pool
}

// TestLiveItemsMatchesTheDirectoriesVTTWrites: the subtitle sweeper keeps what
// LiveItems reports and deletes the rest every hour. If LiveItems and VTT ever
// named a file differently, every live caption directory would read as an
// orphan and the cache would be emptied each run, with nothing failing loudly.
// So this checks the directories VTT actually creates, for every identity form.
func TestLiveItemsMatchesTheDirectoriesVTTWrites(t *testing.T) {
	pool := identityPool(t)
	ctx := context.Background()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "live_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, accID) })
	root := t.TempDir()
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, root).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	items := map[string]string{} // form → item id
	for form, cols := range map[string]struct {
		hash any
		size any
	}{
		"hash":    {"hash-" + suffix, int64(2048)},
		"size":    {nil, int64(4096)},
		"unknown": {nil, nil},
	} {
		name := form + ".mkv"
		if err := os.WriteFile(filepath.Join(root, name), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		var id string
		if err := pool.QueryRow(ctx,
			`INSERT INTO media_items (library_id, kind, title, file_path, content_hash, file_size)
			 VALUES ($1,'movie',$2,$2,$3,$4) RETURNING id::text`, libID, name, cols.hash, cols.size).Scan(&id); err != nil {
			t.Fatal(err)
		}
		items[form] = id
	}

	store := NewStore(pool, "/artwork")
	cache := t.TempDir()
	subs := subtitle.NewService(nil, cache, []string{"en"}, logger)
	for form, id := range items {
		target, ok, err := store.subtitleTarget(ctx, accID, id)
		if err != nil || !ok {
			t.Fatalf("%s: subtitle target: ok %v, err %v", form, ok, err)
		}
		// Fails for want of OpenSubtitles, after making its directory.
		_, _ = subs.VTT(ctx, target, "os:1")
	}

	live := LiveItems{Pool: pool, Logger: logger}.LiveIDs()
	entries, err := os.ReadDir(cache)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != len(items) {
		t.Fatalf("VTT made %d cache dirs, want %d", len(entries), len(items))
	}
	for _, e := range entries {
		if !live[e.Name()] {
			t.Errorf("cache dir %q is written by VTT but not reported live — the sweeper would delete it", e.Name())
		}
	}

	// The hashed item's file is replaced: its old directory is now an orphan.
	oldDir := fileid.ItemKey(items["hash"], "hash-"+suffix)
	if _, err := pool.Exec(ctx, `UPDATE media_items SET content_hash = $2 WHERE id = $1`, items["hash"], "hash-new-"+suffix); err != nil {
		t.Fatal(err)
	}
	live = LiveItems{Pool: pool, Logger: logger}.LiveIDs()
	if live[oldDir] {
		t.Error("a replaced file's caption dir is still reported live")
	}
	if !live[fileid.ItemKey(items["size"], "s4096")] {
		t.Error("an unrelated item's caption dir stopped being live")
	}
}

// TestItemSourceCarriesIdentity: the transcode and stow paths read the file's
// identity in the same query as its path, so the two describe one file.
func TestItemSourceCarriesIdentity(t *testing.T) {
	pool := identityPool(t)
	ctx := context.Background()
	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID, itemID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "src_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, accID) })
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, t.TempDir()).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path, content_hash, file_size)
		 VALUES ($1,'movie','Film','film.mkv','hash-a',100) RETURNING id::text`, libID).Scan(&itemID); err != nil {
		t.Fatal(err)
	}
	src, ok, err := NewStore(pool, "/artwork").itemSource(ctx, accID, itemID)
	if err != nil || !ok {
		t.Fatalf("itemSource: ok %v, err %v", ok, err)
	}
	if src.identity != "hash-a" {
		t.Errorf("identity = %q, want hash-a", src.identity)
	}
	_ = transcode.StartRequest{SourceIdentity: src.identity} // the field the handler fills
}

// TestStowFileAnswersGoneForReplacedSource: a package of a file the library has
// since replaced is never served. It answers 410 — not "not ready yet", which it
// never will be — and the runner re-polls the job for the reason.
func TestStowFileAnswersGoneForReplacedSource(t *testing.T) {
	pool := identityPool(t)
	ctx := context.Background()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	authStore := auth.NewStore(pool)

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	username := "stale_" + suffix
	password := "pw-" + suffix
	acc, err := authStore.CreateAccount(ctx, username, password, "Stale")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, acc.Id.String()) })
	var userID, libID, itemID string
	if err := pool.QueryRow(ctx, `SELECT id::text FROM users WHERE account_id = $1 LIMIT 1`, acc.Id.String()).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		acc.Id.String(), "lib_"+suffix, t.TempDir()).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path, content_hash) VALUES ($1,'movie','Film','film.mkv','hash-1') RETURNING id::text`,
		libID).Scan(&itemID); err != nil {
		t.Fatal(err)
	}
	userUUID := uuid.MustParse(userID)
	reg, err := authStore.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Email: username, Password: password, UserId: &userUUID, DeviceName: "test",
	})
	if err != nil {
		t.Fatal(err)
	}

	workDir := t.TempDir()
	mgr := stow.New(pool, nil, workDir, transcode.EncoderSoftware, 1, 0, logger)
	var jobID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO stow_jobs (account_id, item_id, state, source_identity, output_bytes, ready_at)
		 VALUES ($1, $2, 'ready', 'hash-1', 7, now()) RETURNING id::text`, acc.Id.String(), itemID).Scan(&jobID); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(workDir, jobID), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(mgr.ArtifactPath(jobID), []byte("package"), 0o644); err != nil {
		t.Fatal(err)
	}

	h := stowFileHandler(mgr, authStore, logger)
	call := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/stow/"+jobID+"/file?token="+reg.Token, nil)
		req.SetPathValue("jobId", jobID)
		rec := httptest.NewRecorder()
		h(rec, req)
		return rec
	}

	if rec := call(); rec.Code != http.StatusOK {
		t.Fatalf("before the replacement: status %d, want 200", rec.Code)
	}
	if _, err := pool.Exec(ctx, `UPDATE media_items SET content_hash = 'hash-2' WHERE id = $1`, itemID); err != nil {
		t.Fatal(err)
	}
	rec := call()
	if rec.Code != http.StatusGone {
		t.Fatalf("after the replacement: status %d, want 410", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), stow.StaleMessage) {
		t.Errorf("410 body = %q, want it to carry %q", rec.Body.String(), stow.StaleMessage)
	}
}
