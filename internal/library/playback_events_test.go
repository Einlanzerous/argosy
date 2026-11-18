package library

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/auth"
)

func postPlaybackEvent(h *handlers, itemID, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/items/"+itemID+"/playback-events", strings.NewReader(body))
	req.SetPathValue("itemId", itemID)
	rec := httptest.NewRecorder()
	h.reportPlaybackEvent(rec, req)
	return rec
}

// Without a bearer token the route is a 401 before the handler runs. The
// middleware rejects an empty token without touching its store.
func TestPlaybackEventRequiresAuth(t *testing.T) {
	h := &handlers{logger: testLogger()}
	mw := auth.Middleware(nil)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/items/x/playback-events", strings.NewReader(`{}`))
	rec := httptest.NewRecorder()
	mw(http.HandlerFunc(h.reportPlaybackEvent)).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestPlaybackEventLogsStall(t *testing.T) {
	h, itemID := stowFixture(t, "film.mp4", 1024)
	var buf bytes.Buffer
	h.logger = slog.New(slog.NewTextHandler(&buf, nil))

	rec := postPlaybackEvent(h, itemID, `{"kind":"stall","positionSeconds":812.4,"durationMs":3200,"cause":"play",`+
		`"sessionId":"sess-1","bufferedAheadSeconds":41.26,"delivery":"remux"}`)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204 (body %s)", rec.Code, rec.Body.String())
	}
	out := buf.String()
	if n := strings.Count(out, "playback stall"); n != 1 {
		t.Fatalf("got %d stall lines, want exactly 1:\n%s", n, out)
	}
	for _, want := range []string{
		"item=" + itemID, "session=sess-1", "cause=play", "dur_ms=3200", "ended=true",
		"pos=812.4", "ahead_s=41.3", "delivery=remux", "device=", "account=",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("log line missing %q:\n%s", want, out)
		}
	}
	// ids only: the fixture's title and path must never reach the log.
	for _, banned := range []string{"Film", "film.mp4"} {
		if strings.Contains(out, banned) {
			t.Errorf("log line leaked %q:\n%s", banned, out)
		}
	}

	// An abandoned stall says so, and optional fields collapse to "-".
	buf.Reset()
	rec = postPlaybackEvent(h, itemID, `{"kind":"stall","positionSeconds":5,"durationMs":900,"cause":"seek","ended":false}`)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	out = buf.String()
	for _, want := range []string{"cause=seek", "ended=false", "session=-", "ahead_s=-", "delivery=-"} {
		if !strings.Contains(out, want) {
			t.Errorf("log line missing %q:\n%s", want, out)
		}
	}
}

// A stall that ended in a recovery restart is logged as cut short and
// recovered, never as ended.
func TestPlaybackEventLogsRecovered(t *testing.T) {
	h, itemID := stowFixture(t, "film.mp4", 1024)
	var buf bytes.Buffer
	h.logger = slog.New(slog.NewTextHandler(&buf, nil))

	rec := postPlaybackEvent(h, itemID, `{"kind":"stall","positionSeconds":52,"durationMs":180000,"cause":"play","ended":false,"recovered":true}`)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	out := buf.String()
	for _, want := range []string{"recovered=true", "ended=false", "dur_ms=180000"} {
		if !strings.Contains(out, want) {
			t.Errorf("log line missing %q:\n%s", want, out)
		}
	}
}

func TestPlaybackEventRejectsGarbage(t *testing.T) {
	h, itemID := stowFixture(t, "film.mp4", 1024)
	var buf bytes.Buffer
	h.logger = slog.New(slog.NewTextHandler(&buf, nil))

	cases := map[string]string{
		"not json":       `nope`,
		"empty":          `{}`,
		"unknown kind":   `{"kind":"seek","positionSeconds":1,"durationMs":1,"cause":"play"}`,
		"unknown cause":  `{"kind":"stall","positionSeconds":1,"durationMs":1,"cause":"vibes"}`,
		"negative pos":   `{"kind":"stall","positionSeconds":-1,"durationMs":1,"cause":"play"}`,
		"negative dur":   `{"kind":"stall","positionSeconds":1,"durationMs":-5,"cause":"play"}`,
		"absurd dur":     `{"kind":"stall","positionSeconds":1,"durationMs":999999999999,"cause":"play"}`,
		"negative ahead": `{"kind":"stall","positionSeconds":1,"durationMs":1,"cause":"play","bufferedAheadSeconds":-2}`,
		"bad delivery":   `{"kind":"stall","positionSeconds":1,"durationMs":1,"cause":"play","delivery":"carrier-pigeon"}`,
		"forged session": `{"kind":"stall","positionSeconds":1,"durationMs":1,"cause":"play","sessionId":"a\nlevel=ERROR msg=pwned"}`,
	}
	for name, body := range cases {
		if rec := postPlaybackEvent(h, itemID, body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", name, rec.Code)
		}
	}

	// A well-formed event for an item nobody owns is a 404, not a log line.
	rec := postPlaybackEvent(h, "00000000-0000-0000-0000-0000000000aa",
		`{"kind":"stall","positionSeconds":1,"durationMs":1,"cause":"play"}`)
	if rec.Code != http.StatusNotFound {
		t.Errorf("unknown item: status = %d, want 404", rec.Code)
	}
	if buf.Len() != 0 {
		t.Errorf("rejected events must not log, got:\n%s", buf.String())
	}
}
