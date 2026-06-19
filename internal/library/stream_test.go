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
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestStreamHandler(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run stream tests")
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

	authStore := auth.NewStore(pool)
	store := NewStore(pool, "/artwork")
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	// A real on-disk media file under the library root.
	dir := t.TempDir()
	body := []byte(strings.Repeat("argosy-stream-", 1000)) // 14000 bytes
	if err := os.WriteFile(filepath.Join(dir, "movie.mkv"), body, 0o644); err != nil {
		t.Fatal(err)
	}

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	username := "strm_" + suffix
	password := "pw-" + suffix
	acc, err := authStore.CreateAccount(ctx, username, password, "Stream")
	if err != nil {
		t.Fatal(err)
	}
	var userID string
	if err := pool.QueryRow(ctx, `SELECT id::text FROM users WHERE account_id = $1 LIMIT 1`, acc.Id.String()).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	var libID, itemID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		acc.Id.String(), "lib_"+suffix, dir).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Movie','movie.mkv') RETURNING id::text`,
		libID).Scan(&itemID); err != nil {
		t.Fatal(err)
	}

	reg, err := authStore.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username: username, Password: password, UserId: uuid.MustParse(userID), DeviceName: "test",
	})
	if err != nil {
		t.Fatal(err)
	}
	token := reg.Token

	h := streamHandler(store, authStore, logger)
	call := func(target string, rangeHdr string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, target, nil)
		req.SetPathValue("itemId", itemID)
		if rangeHdr != "" {
			req.Header.Set("Range", rangeHdr)
		}
		rec := httptest.NewRecorder()
		h(rec, req)
		return rec
	}

	// Range request → 206 with exactly the requested bytes.
	rec := call("/api/v1/items/"+itemID+"/stream?token="+token, "bytes=0-9")
	if rec.Code != http.StatusPartialContent {
		t.Fatalf("range status = %d, want 206", rec.Code)
	}
	if rec.Body.Len() != 10 {
		t.Errorf("range body = %d bytes, want 10", rec.Body.Len())
	}
	if rec.Header().Get("Accept-Ranges") != "bytes" || rec.Header().Get("Content-Range") == "" {
		t.Errorf("missing range headers: %+v", rec.Header())
	}
	if ct := rec.Header().Get("Content-Type"); ct != "video/x-matroska" {
		t.Errorf("content-type = %q, want video/x-matroska", ct)
	}

	// Full request → 200, whole file.
	if rec := call("/api/v1/items/"+itemID+"/stream?token="+token, ""); rec.Code != http.StatusOK || rec.Body.Len() != len(body) {
		t.Fatalf("full GET = %d / %d bytes, want 200 / %d", rec.Code, rec.Body.Len(), len(body))
	}

	// No token → 401.
	if rec := call("/api/v1/items/"+itemID+"/stream", ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("no-token status = %d, want 401", rec.Code)
	}

	// A different account's token can't reach this item → 404.
	otherUser := "other_" + suffix
	otherAcc, err := authStore.CreateAccount(ctx, otherUser, password, "Other")
	if err != nil {
		t.Fatal(err)
	}
	var otherUID string
	if err := pool.QueryRow(ctx, `SELECT id::text FROM users WHERE account_id = $1 LIMIT 1`, otherAcc.Id.String()).Scan(&otherUID); err != nil {
		t.Fatal(err)
	}
	otherReg, err := authStore.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username: otherUser, Password: password, UserId: uuid.MustParse(otherUID), DeviceName: "test",
	})
	if err != nil {
		t.Fatal(err)
	}
	if rec := call("/api/v1/items/"+itemID+"/stream?token="+otherReg.Token, ""); rec.Code != http.StatusNotFound {
		t.Errorf("cross-account status = %d, want 404", rec.Code)
	}
}
