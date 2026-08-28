package library

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/jackc/pgx/v5/pgxpool"
)

// specBackend records the Spec it is handed instead of encoding anything, so a
// handler test can assert on the recipe that reached the transcoder.
type specBackend struct {
	mu    sync.Mutex
	specs []transcode.Spec
}

func (*specBackend) Name() string { return "spec-recorder" }

func (b *specBackend) Run(ctx context.Context, spec transcode.Spec, _ func(transcode.Progress)) error {
	b.mu.Lock()
	b.specs = append(b.specs, spec)
	b.mu.Unlock()
	<-ctx.Done()
	return nil
}

// await waits for the session goroutine to hand the backend its spec.
func (b *specBackend) await(t *testing.T) transcode.Spec {
	t.Helper()
	for range 200 {
		b.mu.Lock()
		n := len(b.specs)
		last := transcode.Spec{}
		if n > 0 {
			last = b.specs[n-1]
		}
		b.mu.Unlock()
		if n > 0 {
			return last
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("backend was never handed a spec")
	return transcode.Spec{}
}

// burnInFixture seeds an item whose ffprobe JSON carries a text subtitle, an
// image subtitle, and browser-friendly video/audio — so the item would remux if
// nothing were burned in, which is what makes the override observable.
func burnInFixture(t *testing.T) (*handlers, *specBackend, string) {
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
	if err := os.WriteFile(filepath.Join(root, "film.mkv"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := pool.Exec(ctx, `DELETE FROM accounts WHERE id = $1`, zeroAccount); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO accounts (id, name) VALUES ($1,$2)`, zeroAccount, "burnin_handler"); err != nil {
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
	technical := `{"streams":[
		{"index":0,"codec_type":"video","codec_name":"h264","height":1080,"pix_fmt":"yuv420p"},
		{"index":1,"codec_type":"audio","codec_name":"aac"},
		{"index":2,"codec_type":"subtitle","codec_name":"subrip","tags":{"language":"eng"}},
		{"index":3,"codec_type":"subtitle","codec_name":"hdmv_pgs_subtitle","tags":{"language":"eng"}}
	]}`
	if err := pool.QueryRow(ctx,
		`INSERT INTO media_items (library_id, kind, title, file_path, duration_seconds, technical)
		 VALUES ($1,'movie','Film',$2,$3,$4) RETURNING id::text`,
		libID, "film.mkv", 5400.0, technical).Scan(&itemID); err != nil {
		t.Fatal(err)
	}

	be := &specBackend{}
	m := transcode.NewManager(be, t.TempDir(), time.Minute, 4, testLogger())
	t.Cleanup(func() {
		for _, s := range m.List() {
			m.Stop(s.ID)
		}
	})
	return &handlers{
		store:   NewStore(pool, "/artwork"),
		logger:  testLogger(),
		tc:      m,
		encoder: transcode.EncoderSoftware,
	}, be, itemID
}

func postTranscode(t *testing.T, h *handlers, itemID, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/items/"+itemID+"/transcode", strings.NewReader(body))
	req.SetPathValue("itemId", itemID)
	rec := httptest.NewRecorder()
	h.startTranscode(rec, req)
	return rec
}

// TestStartTranscodeBurnsInSelectedTrack is the ARGY-59 happy path. The fixture
// is H.264/AAC, which normally remuxes — a copy that would carry no subtitle —
// so selecting the image track has to turn the session into a re-encode with the
// stream index attached.
func TestStartTranscodeBurnsInSelectedTrack(t *testing.T) {
	h, be, itemID := burnInFixture(t)

	rec := postTranscode(t, h, itemID, `{"burnInSubtitle":"burn:3"}`)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202 (body %s)", rec.Code, rec.Body.String())
	}
	spec := be.await(t)
	if spec.Method != transcode.MethodTranscode {
		t.Errorf("method = %q, want %q — a copied stream carries no burned-in subtitle",
			spec.Method, transcode.MethodTranscode)
	}
	if spec.BurnInSubtitle != 3 {
		t.Errorf("BurnInSubtitle = %d, want 3", spec.BurnInSubtitle)
	}
}

// TestStartTranscodeWithoutBurnInStillRemuxes: the same item, no track selected,
// must take the cheap path exactly as before. This is the regression half —
// burn-in must cost a re-encode only for the viewer who asked for it.
func TestStartTranscodeWithoutBurnInStillRemuxes(t *testing.T) {
	h, be, itemID := burnInFixture(t)

	for _, body := range []string{``, `{}`, `{"burnInSubtitle":""}`} {
		rec := postTranscode(t, h, itemID, body)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("body %q: status = %d, want 202 (%s)", body, rec.Code, rec.Body.String())
		}
	}
	spec := be.await(t)
	if spec.Method != transcode.MethodRemux {
		t.Errorf("method = %q, want %q for an unsubtitled H.264/AAC source", spec.Method, transcode.MethodRemux)
	}
	if spec.BurnInSubtitle != 0 {
		t.Errorf("BurnInSubtitle = %d, want 0", spec.BurnInSubtitle)
	}
}

// TestStartTranscodeRejectsUnburnableTrack: the index reaches an ffmpeg
// filtergraph, so anything that isn't an image subtitle of this item is refused
// with a 400 rather than started and left to fail at encode time — where the
// client sees only a session that never produces a playlist.
func TestStartTranscodeRejectsUnburnableTrack(t *testing.T) {
	h, be, itemID := burnInFixture(t)

	for _, id := range []string{
		"burn:0",     // the video stream
		"burn:1",     // audio
		"burn:2",     // the text subtitle — belongs to the WebVTT path
		"burn:7",     // no such stream
		"embedded:3", // right stream, wrong prefix
		"burn:x",     // not an index
	} {
		rec := postTranscode(t, h, itemID, `{"burnInSubtitle":"`+id+`"}`)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400 (body %s)", id, rec.Code, rec.Body.String())
		}
	}
	be.mu.Lock()
	started := len(be.specs)
	be.mu.Unlock()
	if started != 0 {
		t.Errorf("%d sessions started for refused tracks; want none", started)
	}
}
