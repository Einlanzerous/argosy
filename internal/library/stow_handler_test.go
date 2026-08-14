package library

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

// zeroAccount is the account id accountOf resolves to for a request carrying no
// auth session. The auth context keys are unexported, so a handler test scopes
// its fixture to this id rather than injecting a session — the same trick the
// transcode session test uses, from the other end.
const zeroAccount = "00000000-0000-0000-0000-000000000000"

// stowFixture seeds an account/library/item whose media file really exists on
// disk, since the stow decision stats it for size.
func stowFixture(t *testing.T, filename string, size int) (*handlers, string) {
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

	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, filename), make([]byte, size), 0o644); err != nil {
		t.Fatal(err)
	}

	// Claim the zero account for this test, clearing any wreckage from a
	// previous failed run.
	if _, err := pool.Exec(ctx, `DELETE FROM accounts WHERE id = $1`, zeroAccount); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO accounts (id, name) VALUES ($1, $2)`, zeroAccount, "stow_handler"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, zeroAccount)
	})

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var libID, itemID string
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		zeroAccount, "lib_"+suffix, root).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	// technical mirrors what the scanner stores from ffprobe.
	technical := `{"streams":[{"codec_type":"video","codec_name":"h264","height":1080,"pix_fmt":"yuv420p"},{"codec_type":"audio","codec_name":"aac"}]}`
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path, duration_seconds, technical)
		 VALUES ($1,'movie','Film',$2,$3,$4) RETURNING id::text`,
		libID, filename, 5400.0, technical).Scan(&itemID); err != nil {
		t.Fatal(err)
	}

	return &handlers{
		store:              NewStore(pool, "/artwork"),
		logger:             testLogger(),
		stowPassthroughMax: DefaultStowPassthroughMax,
	}, itemID
}

func postStow(t *testing.T, h *handlers, itemID, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/items/"+itemID+"/stow", reader)
	req.SetPathValue("itemId", itemID)
	rec := httptest.NewRecorder()
	h.stowItem(rec, req)
	return rec
}

// TestStowItemPassthrough is the shape the client depends on for the cheap path:
// ready immediately, pointed at the existing stream endpoint, with no job id
// because nothing is being made.
func TestStowItemPassthrough(t *testing.T) {
	h, itemID := stowFixture(t, "film.mp4", 1024)

	rec := postStow(t, h, itemID, "")
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202 (body %s)", rec.Code, rec.Body.String())
	}
	var got api.StowJob
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode: %v (body %s)", err, rec.Body.String())
	}
	if got.Method != api.Passthrough {
		t.Errorf("method = %q, want passthrough for an h264/aac mp4", got.Method)
	}
	if got.State != api.StowJobStateReady {
		t.Errorf("state = %q, want ready — there is nothing to wait for", got.State)
	}
	if got.Id != nil {
		t.Errorf("id = %v, want none; a passthrough leaves no server-side job", *got.Id)
	}
	if got.DownloadUrl == nil || *got.DownloadUrl != "/api/v1/items/"+itemID+"/stream" {
		t.Errorf("downloadUrl = %v, want the stream endpoint", got.DownloadUrl)
	}
	if got.Bytes == nil || *got.Bytes != 1024 {
		t.Errorf("bytes = %v, want the source size", got.Bytes)
	}
	if got.DurationSeconds == nil || *got.DurationSeconds != 5400 {
		t.Errorf("durationSeconds = %v, want 5400", got.DurationSeconds)
	}
	if got.Reason == nil || *got.Reason == "" {
		t.Error("reason is empty; the UI explains the choice with it")
	}
}

// TestStowItemNeedsPackagingWithoutManager covers the honest failure when a stow
// needs an encode on a server that has packaging disabled — it must say so
// rather than pretending the file is ready.
func TestStowItemNeedsPackagingWithoutManager(t *testing.T) {
	// .avi is outside every mobile container set, so this must package.
	h, itemID := stowFixture(t, "old.avi", 1024)

	rec := postStow(t, h, itemID, "")
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 when packaging is disabled (body %s)", rec.Code, rec.Body.String())
	}
}

// TestStowItemUnknownItem404s guards the scoping: an item id that isn't in this
// account's catalog must not leak that it exists elsewhere.
func TestStowItemUnknownItem404s(t *testing.T) {
	h, _ := stowFixture(t, "film.mp4", 1024)

	rec := postStow(t, h, "11111111-2222-3333-4444-555555555555", "")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 (body %s)", rec.Code, rec.Body.String())
	}
}

// TestStowItemMissingFile404s covers a catalog row whose file is gone (a dropped
// mount, or a rename the scanner hasn't caught up with): stowing something
// unreadable must fail here, not halfway through a download.
func TestStowItemMissingFile404s(t *testing.T) {
	h, itemID := stowFixture(t, "film.mp4", 1024)

	root, rel, ok, err := h.store.itemPath(context.Background(), zeroAccount, itemID)
	if err != nil || !ok {
		t.Fatalf("resolve item path: %v, %v", ok, err)
	}
	if err := os.Remove(filepath.Join(root, rel)); err != nil {
		t.Fatal(err)
	}

	rec := postStow(t, h, itemID, "")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404 when the media file is gone (body %s)", rec.Code, rec.Body.String())
	}
}
