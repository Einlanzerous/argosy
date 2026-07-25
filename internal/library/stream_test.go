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
	// The media lives in the *instance owner's* library while the device signs in
	// on the freshly created account above. That is the ARGY-167 shape: a member
	// household streams from the server's catalog, not from its own empty one.
	var libID, itemID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		ownerAccountID(ctx, t, pool), "lib_"+suffix, dir).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Movie','movie.mkv') RETURNING id::text`,
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

	// Another household streams the same item fine: every account browses the
	// instance owner's catalog (ARGY-167). Before ownership existed this was a
	// 404, which is precisely why invited members saw an empty server.
	otherUser := "other_" + suffix
	otherAcc, err := authStore.CreateAccount(ctx, otherUser, password, "Other")
	if err != nil {
		t.Fatal(err)
	}
	var otherUID string
	if err := pool.QueryRow(ctx, `SELECT id::text FROM users WHERE account_id = $1 LIMIT 1`, otherAcc.Id.String()).Scan(&otherUID); err != nil {
		t.Fatal(err)
	}
	otherUUID := uuid.MustParse(otherUID)
	otherReg, err := authStore.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Email: otherUser, Password: password, UserId: &otherUUID, DeviceName: "test",
	})
	if err != nil {
		t.Fatal(err)
	}
	if rec := call("/api/v1/items/"+itemID+"/stream?token="+otherReg.Token, ""); rec.Code != http.StatusOK {
		t.Errorf("member household status = %d, want 200 (the owner's catalog is shared)", rec.Code)
	}

	// Sharing the catalog must not mean serving *anything*: media parked under a
	// library that isn't the owner's stays unreachable, even to the account that
	// owns that library.
	strayFile := "stray.mkv"
	if err := os.WriteFile(filepath.Join(dir, strayFile), body, 0o644); err != nil {
		t.Fatal(err)
	}
	var strayLib, strayItem string
	if err := pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		otherAcc.Id.String(), "stray_"+suffix, dir).Scan(&strayLib); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Stray',$2) RETURNING id::text`,
		strayLib, strayFile).Scan(&strayItem); err != nil {
		t.Fatal(err)
	}
	strayReq := func(token string) int {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/items/"+strayItem+"/stream?token="+token, nil)
		req.SetPathValue("itemId", strayItem)
		rec := httptest.NewRecorder()
		h(rec, req)
		return rec.Code
	}
	if code := strayReq(otherReg.Token); code != http.StatusNotFound {
		t.Errorf("stray item, owning account = %d, want 404 (outside the catalog)", code)
	}
	if code := strayReq(token); code != http.StatusNotFound {
		t.Errorf("stray item, other account = %d, want 404 (outside the catalog)", code)
	}
}
