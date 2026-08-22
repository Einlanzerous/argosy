package library

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/beacon"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// streamWriter is a ResponseWriter the test can watch while the handler is
// still writing to it. httptest.ResponseRecorder isn't safe for that — the
// handler goroutine appends to Body while the test reads it — so this guards
// the buffer and closes `opened` on the first write instead.
type streamWriter struct {
	mu     sync.Mutex
	buf    bytes.Buffer
	hdr    http.Header
	opened chan struct{}
	once   sync.Once
}

func newStreamWriter() *streamWriter {
	return &streamWriter{hdr: make(http.Header), opened: make(chan struct{})}
}

func (w *streamWriter) Header() http.Header { return w.hdr }
func (w *streamWriter) WriteHeader(int)     {}
func (w *streamWriter) Flush()              {}

func (w *streamWriter) Write(b []byte) (int, error) {
	w.mu.Lock()
	n, err := w.buf.Write(b)
	w.mu.Unlock()
	w.once.Do(func() { close(w.opened) })
	return n, err
}

func (w *streamWriter) body() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.buf.String()
}

// TestBeaconStreamEndsOnHubDrain is the regression guard for ARGY-194.
//
// A Beacon stream sits in its select loop for as long as the client is
// connected, which means the connection is *active*, never idle.
// http.Server.Shutdown waits for connections to go idle and does not cancel
// in-flight request contexts, so a single browser tab on Home held every
// shutdown to its full 10s deadline — and Docker's stop timeout is also 10s, so
// each deploy ended in a SIGKILL and a non-zero exit.
//
// The request context here is never cancelled (httptest.NewRequest carries a
// Background context), so the only thing that can end this handler is the hub
// draining. If that case is ever dropped from the select, this hangs.
func TestBeaconStreamEndsOnHubDrain(t *testing.T) {
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

	authStore := auth.NewStore(pool)
	hub := beacon.NewHub(pool, slog.New(slog.NewTextHandler(io.Discard, nil)))

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	username := "bcn_" + suffix
	password := "pw-" + suffix
	acc, err := authStore.CreateAccount(ctx, username, password, "Beacon")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, acc.Id.String())
	})
	var userID string
	if err := pool.QueryRow(ctx,
		`SELECT id::text FROM users WHERE account_id = $1 LIMIT 1`, acc.Id.String()).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	userUUID := uuid.MustParse(userID)
	reg, err := authStore.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Email: username, Password: password, UserId: &userUUID, DeviceName: "test",
	})
	if err != nil {
		t.Fatal(err)
	}

	w := newStreamWriter()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/beacon?token="+reg.Token, nil)

	returned := make(chan struct{})
	go func() {
		beaconHandler(authStore, hub)(w, req)
		close(returned)
	}()

	// Wait for the stream to actually open, so closing the hub can't race the
	// handler into its select and pass for the wrong reason.
	select {
	case <-w.opened:
	case <-time.After(10 * time.Second):
		t.Fatalf("stream never opened; body = %q", w.body())
	}

	hub.Close()

	select {
	case <-returned:
	case <-time.After(10 * time.Second):
		t.Fatal("handler still streaming after the hub drained — Shutdown would burn its full deadline")
	}
}
