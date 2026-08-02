package library

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/transcode"
)

func testLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

// hevcMaster is what ffmpeg writes for an HEVC variant, malformed constraint
// byte and all. See transcode.NormalizePlaylist (ARGY-174).
const hevcMaster = `#EXTM3U
#EXT-X-VERSION:7
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="group_aud",NAME="audio_1",DEFAULT=YES,LANGUAGE="ja",URI="stream_1.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=8940800,RESOLUTION=1920x1080,CODECS="hvc1.1.4.L120.B01,mp4a.40.2",AUDIO="group_aud"
stream_0.m3u8
`

// writeBackend drops a fixed set of files into the session's output dir, the
// way a real encode would, and returns.
type writeBackend struct{ files map[string]string }

func (writeBackend) Name() string { return "write" }

func (b writeBackend) Run(_ context.Context, spec transcode.Spec, _ func(transcode.Progress)) error {
	for name, body := range b.files {
		if err := os.WriteFile(filepath.Join(spec.OutputDir, name), []byte(body), 0o644); err != nil {
			return err
		}
	}
	return nil
}

// transcodeSessionFor starts a session the returned request will be allowed to
// read. The request carries no auth session, so accountOf resolves the zero
// account — deriving the session's owner from the same function the handler
// uses keeps the two in step without standing up a database.
func transcodeSessionFor(t *testing.T, be transcode.Backend, files ...string) (*handlers, transcode.Session) {
	t.Helper()
	m := transcode.NewManager(be, t.TempDir(), time.Minute, 4, testLogger())
	sess, err := m.Start(transcode.StartRequest{
		ItemID:    "item-1",
		AccountID: accountOf(httptest.NewRequest(http.MethodGet, "/", nil)),
		Source:    "/x/y.mkv",
		Encoder:   transcode.EncoderSoftware,
	})
	if err != nil {
		t.Fatalf("start session: %v", err)
	}
	t.Cleanup(func() { m.Stop(sess.ID) })

	// The backend runs in a goroutine; wait for what this test needs.
	for _, name := range files {
		path := filepath.Join(sess.OutputDir, name)
		var ok bool
		for i := 0; i < 100 && !ok; i++ {
			if _, err := os.Stat(path); err == nil {
				ok = true
				break
			}
			time.Sleep(10 * time.Millisecond)
		}
		if !ok {
			t.Fatalf("backend never wrote %s", name)
		}
	}
	return &handlers{tc: m, logger: testLogger()}, sess
}

func getTranscodeFile(h *handlers, sess transcode.Session, name string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/transcode/"+sess.ID+"/"+name, nil)
	req.SetPathValue("sessionId", sess.ID)
	req.SetPathValue("file", name)
	rec := httptest.NewRecorder()
	h.fileTranscode(rec, req)
	return rec
}

// TestFileTranscodeNormalizesServedPlaylist is the wiring guard for ARGY-174:
// the rewrite has to be in the response path, not merely available. Asserting
// on NormalizePlaylist directly would keep passing if the call site were
// dropped, which is precisely how this bug reached production.
func TestFileTranscodeNormalizesServedPlaylist(t *testing.T) {
	h, sess := transcodeSessionFor(t,
		writeBackend{files: map[string]string{transcode.PlaylistName: hevcMaster}},
		transcode.PlaylistName)

	rec := getTranscodeFile(h, sess, transcode.PlaylistName)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	body := rec.Body.String()
	if strings.Contains(body, ".B01") {
		t.Errorf("served playlist still carries the malformed constraint byte:\n%s", body)
	}
	if !strings.Contains(body, `CODECS="hvc1.1.4.L120.B0,mp4a.40.2"`) {
		t.Errorf("served playlist missing the normalized codec string:\n%s", body)
	}

	// ffmpeg's own output is left alone; only what goes out is rewritten.
	onDisk, err := os.ReadFile(filepath.Join(sess.OutputDir, transcode.PlaylistName))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(onDisk), ".B01") {
		t.Errorf("the on-disk playlist was modified:\n%s", onDisk)
	}
}

// TestFileTranscodeRecordsWhatWasServed pins the ordering the stall signal
// depends on: only artifacts that actually went out count. Marking on entry
// would score the 503 a client gets while the manifest is still being written
// as "served", and the signal reads backwards on exactly the failure it exists
// to name.
func TestFileTranscodeRecordsWhatWasServed(t *testing.T) {
	t.Run("503 while the manifest is unwritten", func(t *testing.T) {
		h, sess := transcodeSessionFor(t, writeBackend{})

		if rec := getTranscodeFile(h, sess, transcode.PlaylistName); rec.Code != http.StatusServiceUnavailable {
			t.Fatalf("status = %d, want 503", rec.Code)
		}
		snap, _ := h.tc.Get(sess.ID)
		if snap.ServedPlaylist {
			t.Error("a 503 was recorded as a served playlist")
		}
	})

	t.Run("404 for a missing segment", func(t *testing.T) {
		h, sess := transcodeSessionFor(t,
			writeBackend{files: map[string]string{transcode.PlaylistName: hevcMaster}},
			transcode.PlaylistName)

		if rec := getTranscodeFile(h, sess, "stream_0_00000.m4s"); rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, want 404", rec.Code)
		}
		snap, _ := h.tc.Get(sess.ID)
		if snap.ServedSegment {
			t.Error("a 404 was recorded as a served segment")
		}
	})

	t.Run("successful fetches", func(t *testing.T) {
		h, sess := transcodeSessionFor(t, writeBackend{files: map[string]string{
			transcode.PlaylistName: hevcMaster,
			"stream_0_00000.m4s":   "segment-bytes",
		}}, transcode.PlaylistName, "stream_0_00000.m4s")

		if rec := getTranscodeFile(h, sess, transcode.PlaylistName); rec.Code != http.StatusOK {
			t.Fatalf("playlist status = %d, want 200", rec.Code)
		}
		if snap, _ := h.tc.Get(sess.ID); !snap.ServedPlaylist || snap.ServedSegment {
			t.Errorf("after the playlist: ServedPlaylist=%v ServedSegment=%v, want true/false",
				snap.ServedPlaylist, snap.ServedSegment)
		}
		if rec := getTranscodeFile(h, sess, "stream_0_00000.m4s"); rec.Code != http.StatusOK {
			t.Fatalf("segment status = %d, want 200", rec.Code)
		}
		if snap, _ := h.tc.Get(sess.ID); !snap.ServedSegment {
			t.Error("a served segment was not recorded")
		}
	})
}
