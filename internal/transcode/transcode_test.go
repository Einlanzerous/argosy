package transcode

import (
	"context"
	"io"
	"log/slog"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func discardLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

// blockingBackend blocks in Run until ctx is cancelled, optionally emitting one
// progress update first. It records how many times Run was invoked.
type blockingBackend struct {
	progress Progress
	mu       sync.Mutex
	runs     int
}

func (b *blockingBackend) Name() string { return "blocking" }

func (b *blockingBackend) Run(ctx context.Context, _ Spec, onProgress func(Progress)) error {
	b.mu.Lock()
	b.runs++
	b.mu.Unlock()
	if onProgress != nil && b.progress != (Progress{}) {
		onProgress(b.progress)
	}
	<-ctx.Done()
	return ctx.Err()
}

func (b *blockingBackend) runCount() int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.runs
}

// instantBackend returns immediately, simulating a fast completion.
type instantBackend struct{}

func (instantBackend) Name() string                                    { return "instant" }
func (instantBackend) Run(context.Context, Spec, func(Progress)) error { return nil }

func newReq(item string) StartRequest {
	return StartRequest{ItemID: item, AccountID: "acct-1", Source: "/x/y.mkv", Encoder: EncoderSoftware}
}

func TestStartJoinsExistingSession(t *testing.T) {
	be := &blockingBackend{progress: Progress{OutTimeMS: 1000, Speed: 2.5}}
	m := NewManager(be, t.TempDir(), 10*time.Second, 4, discardLogger())

	first, err := m.Start(newReq("item-1"))
	if err != nil {
		t.Fatalf("first start: %v", err)
	}
	second, err := m.Start(newReq("item-1"))
	if err != nil {
		t.Fatalf("second start: %v", err)
	}
	if first.ID != second.ID {
		t.Fatalf("expected same session id, got %q and %q", first.ID, second.ID)
	}
	if got := len(m.List()); got != 1 {
		t.Fatalf("expected 1 live session, got %d", got)
	}
	// Only one ffmpeg should ever have been launched for the joined session.
	// (Allow the run goroutine a moment to invoke the backend.)
	waitFor(t, func() bool { return be.runCount() == 1 })

	if !m.Stop(first.ID) {
		t.Fatal("Stop returned false for a live session")
	}
	if _, ok := m.Get(first.ID); ok {
		t.Fatal("session still present after Stop")
	}
	if _, err := os.Stat(first.OutputDir); !os.IsNotExist(err) {
		t.Fatalf("output dir not purged after Stop: %v", err)
	}
}

func TestStartCapacityBackpressure(t *testing.T) {
	m := NewManager(&blockingBackend{}, t.TempDir(), 10*time.Second, 1, discardLogger())

	if _, err := m.Start(newReq("item-1")); err != nil {
		t.Fatalf("first start: %v", err)
	}
	_, err := m.Start(newReq("item-2"))
	if err != ErrAtCapacity {
		t.Fatalf("expected ErrAtCapacity, got %v", err)
	}
}

func TestReapKillsIdleSessions(t *testing.T) {
	be := &blockingBackend{}
	m := NewManager(be, t.TempDir(), 10*time.Second, 4, discardLogger())
	base := time.Now()
	m.clock = func() time.Time { return base }

	s, err := m.Start(newReq("item-1"))
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	waitFor(t, func() bool { return be.runCount() == 1 })

	// Not yet idle.
	m.reap()
	if _, ok := m.Get(s.ID); !ok {
		t.Fatal("session reaped before idle TTL elapsed")
	}

	// Advance past the idle TTL → reaped + purged.
	m.clock = func() time.Time { return base.Add(11 * time.Second) }
	m.reap()
	if _, ok := m.Get(s.ID); ok {
		t.Fatal("idle session not reaped")
	}
	if _, err := os.Stat(s.OutputDir); !os.IsNotExist(err) {
		t.Fatalf("output dir not purged on reap: %v", err)
	}
}

func TestTouchKeepsSessionAlive(t *testing.T) {
	m := NewManager(&blockingBackend{}, t.TempDir(), 10*time.Second, 4, discardLogger())
	base := time.Now()
	m.clock = func() time.Time { return base }
	s, _ := m.Start(newReq("item-1"))

	// Access just before the cutoff keeps it alive across a later reap.
	m.clock = func() time.Time { return base.Add(9 * time.Second) }
	if !m.Touch(s.ID) {
		t.Fatal("Touch returned false")
	}
	m.clock = func() time.Time { return base.Add(11 * time.Second) }
	m.reap()
	if _, ok := m.Get(s.ID); !ok {
		t.Fatal("recently-touched session was reaped")
	}
}

func TestCompletedSessionRemains(t *testing.T) {
	m := NewManager(instantBackend{}, t.TempDir(), 10*time.Second, 4, discardLogger())
	s, err := m.Start(newReq("item-1"))
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	waitFor(t, func() bool {
		got, ok := m.Get(s.ID)
		return ok && got.State == StateComplete
	})
}

func TestRunShutsDownSessions(t *testing.T) {
	m := NewManager(&blockingBackend{}, t.TempDir(), 10*time.Second, 4, discardLogger())
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { m.Run(ctx); close(done) }()

	s, _ := m.Start(newReq("item-1"))
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after ctx cancel")
	}
	if _, ok := m.Get(s.ID); ok {
		t.Fatal("session not shut down when Run exited")
	}
}

func TestSessionIDDeterministicAndScoped(t *testing.T) {
	a := sessionID(StartRequest{ItemID: "i", AccountID: "acct-1", StartAt: 0, Encoder: "software"})
	b := sessionID(StartRequest{ItemID: "i", AccountID: "acct-1", StartAt: 0, Encoder: "software"})
	if a != b {
		t.Fatalf("ids not deterministic: %q vs %q", a, b)
	}
	other := sessionID(StartRequest{ItemID: "i", AccountID: "acct-2", StartAt: 0, Encoder: "software"})
	if a == other {
		t.Fatal("ids not account-scoped")
	}
	seek := sessionID(StartRequest{ItemID: "i", AccountID: "acct-1", StartAt: 30, Encoder: "software"})
	if a == seek {
		t.Fatal("ids not offset-scoped")
	}
}

func TestBuildArgsHLSLadder(t *testing.T) {
	// 1080p source → full 3-rung ladder.
	args := buildArgs(Spec{Source: "/m/a.mkv", OutputDir: "/tmp/out", StartAt: 30, Encoder: EncoderSoftware, SourceHeight: 1080})
	joined := strings.Join(args, " ")
	for _, want := range []string{
		"-i /m/a.mkv", "libx264", "-ss 30.000",
		"-filter_complex", "split=3", "scale=-2:1080", "scale=-2:480",
		"-var_stream_map v:0,a:0 v:1,a:1 v:2,a:2",
		"-master_pl_name " + PlaylistName,
		"-hls_segment_type fmp4", "stream_%v.m3u8",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("args missing %q\nargs: %s", want, joined)
		}
	}
}

func TestRungsFor(t *testing.T) {
	cases := []struct {
		height int
		want   int
	}{
		{1080, 3}, {1440, 3}, {720, 2}, {600, 1}, {480, 1}, {360, 1}, {0, 1},
	}
	for _, c := range cases {
		if got := len(rungsFor(c.height)); got != c.want {
			t.Errorf("rungsFor(%d) = %d rungs, want %d", c.height, got, c.want)
		}
	}
	// Never upscale: a 480p source's top rung is ≤ 480.
	if r := rungsFor(480); r[0].height > 480 {
		t.Errorf("rungsFor(480) top rung %d upscales", r[0].height)
	}
}

func TestParseProgress(t *testing.T) {
	in := "frame=10\nfps=24.0\nspeed=2.53x\nout_time_us=4000000\nprogress=continue\n"
	var got Progress
	parseProgress(strings.NewReader(in), func(p Progress) { got = p })
	if got.OutTimeMS != 4000 {
		t.Errorf("OutTimeMS = %d, want 4000", got.OutTimeMS)
	}
	if got.Speed != 2.53 {
		t.Errorf("Speed = %v, want 2.53", got.Speed)
	}
	if got.FPS != 24.0 {
		t.Errorf("FPS = %v, want 24.0", got.FPS)
	}
}

// waitFor polls cond for up to a second so tests don't race the run goroutine.
func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("condition not met within timeout")
}
