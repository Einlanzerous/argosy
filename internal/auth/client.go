package auth

import (
	"context"
	"log/slog"
	"strings"
	"sync"
	"time"
)

// ClientHeader is the request header every Argosy client sends to say which
// build it is (ARGY-262), e.g. `argosy-android/0.32.0+78 (Pixel 9; Android 36)`.
const ClientHeader = "X-Argosy-Client"

// clientRefresh is how stale the stored last_client_at may get before an
// unchanged client string is written again. Segment requests are hot; the write
// must not be one per request.
const clientRefresh = time.Hour

const maxClientLen = 200

// Trace is a per-request mutable slot that withLogging puts on the context so
// the log line can read, after next.ServeHTTP, who the auth layer resolved.
// Authentication happens deep in the handler chain (several places call
// AuthenticateDevice), so a shared pointer is the only way the outer logger
// sees it.
type Trace struct {
	// Client is the sanitized X-Argosy-Client value, set by the logger.
	Client string

	mu         sync.Mutex
	accountID  string
	deviceID   string
	deviceName string
}

// Identity returns the resolved account id, device id and device name; empty
// strings when the request was never authenticated.
func (t *Trace) Identity() (accountID, deviceID, deviceName string) {
	if t == nil {
		return "", "", ""
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.accountID, t.deviceID, t.deviceName
}

// SetIdentity is called by the auth layer once a bearer token resolves.
func (t *Trace) SetIdentity(accountID, deviceID, deviceName string) {
	t.mu.Lock()
	t.accountID, t.deviceID, t.deviceName = accountID, deviceID, deviceName
	t.mu.Unlock()
}

type traceKey struct{}

// WithTrace returns ctx carrying t.
func WithTrace(ctx context.Context, t *Trace) context.Context {
	return context.WithValue(ctx, traceKey{}, t)
}

// TraceFromContext returns the request's Trace, or nil.
func TraceFromContext(ctx context.Context) *Trace {
	t, _ := ctx.Value(traceKey{}).(*Trace)
	return t
}

// DeviceLabel is the device's name for log lines (short id if unnamed), or "-"
// when the request is unauthenticated or has no trace.
func DeviceLabel(ctx context.Context) string {
	_, id, name := TraceFromContext(ctx).Identity()
	switch {
	case name != "":
		return name
	case id != "":
		return id[:min(8, len(id))]
	}
	return "-"
}

// SanitizeClient trims a raw X-Argosy-Client value to something safe to log and
// store: printable characters only, bounded length.
func SanitizeClient(raw string) string {
	raw = strings.TrimSpace(raw)
	var b strings.Builder
	for _, r := range raw {
		if r < 0x20 || r == 0x7f {
			continue
		}
		b.WriteRune(r)
		if b.Len() >= maxClientLen {
			break
		}
	}
	return b.String()
}

type clientStamp struct {
	client string
	at     time.Time
}

// clientTracker decides when a device's last_client needs writing. The
// in-memory map makes the common case (same client, written recently) free of
// DB work; the stored values seed it after a restart.
type clientTracker struct {
	seen sync.Map // device id -> clientStamp
	now  func() time.Time
}

func (c *clientTracker) clock() time.Time {
	if c.now != nil {
		return c.now()
	}
	return time.Now()
}

// needsWrite reports whether client must be persisted for deviceID, given the
// values already stored on the row.
func (c *clientTracker) needsWrite(deviceID, client, storedClient string, storedAt *time.Time) bool {
	if client == "" {
		return false
	}
	now := c.clock()
	if v, ok := c.seen.Load(deviceID); ok {
		s := v.(clientStamp)
		return s.client != client || now.Sub(s.at) >= clientRefresh
	}
	if storedAt != nil && storedClient == client && now.Sub(*storedAt) < clientRefresh {
		c.seen.Store(deviceID, clientStamp{client: client, at: *storedAt})
		return false
	}
	return true
}

func (c *clientTracker) wrote(deviceID, client string) {
	c.seen.Store(deviceID, clientStamp{client: client, at: c.clock()})
}

// noteClient persists the client string if it is new or stale. It never fails
// the request: a write error is logged at debug and dropped.
func (s *Store) noteClient(ctx context.Context, deviceID, client, storedClient string, storedAt *time.Time) {
	if !s.clients.needsWrite(deviceID, client, storedClient, storedAt) {
		return
	}
	if _, err := s.pool.Exec(ctx,
		`UPDATE devices SET last_client = $1, last_client_at = now() WHERE id = $2`, client, deviceID); err != nil {
		slog.Debug("auth: record device client failed", "device", deviceID, "err", err)
		return
	}
	s.clients.wrote(deviceID, client)
}
