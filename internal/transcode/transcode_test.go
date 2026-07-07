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

// TestTouchItemKeepsBufferedSessionAlive covers ARGY-94: a client buffered far
// ahead stops fetching segments (no Touch) but keeps sending progress, which
// calls TouchItem(account, item). That must keep the transcode alive across a
// reap that would otherwise kill it.
func TestTouchItemKeepsBufferedSessionAlive(t *testing.T) {
	m := NewManager(&blockingBackend{}, t.TempDir(), 10*time.Second, 4, discardLogger())
	base := time.Now()
	m.clock = func() time.Time { return base }
	s, _ := m.Start(newReq("item-1")) // newReq uses AccountID "acct-1"

	// No segment Touch — only a progress heartbeat just before the cutoff.
	m.clock = func() time.Time { return base.Add(9 * time.Second) }
	if n := m.TouchItem("acct-1", "item-1"); n != 1 {
		t.Fatalf("TouchItem matched %d sessions, want 1", n)
	}
	m.clock = func() time.Time { return base.Add(11 * time.Second) }
	m.reap()
	if _, ok := m.Get(s.ID); !ok {
		t.Fatal("session reaped despite a progress heartbeat keeping it alive")
	}
}

// TestTouchItemIgnoresOtherAccountsAndItems guards the match: a heartbeat for a
// different account or item must not keep this session alive (no cross-talk).
func TestTouchItemIgnoresOtherAccountsAndItems(t *testing.T) {
	m := NewManager(&blockingBackend{}, t.TempDir(), 10*time.Second, 4, discardLogger())
	base := time.Now()
	m.clock = func() time.Time { return base }
	s, _ := m.Start(newReq("item-1")) // acct-1 / item-1

	m.clock = func() time.Time { return base.Add(9 * time.Second) }
	if n := m.TouchItem("acct-2", "item-1"); n != 0 {
		t.Fatalf("TouchItem matched a foreign account: %d", n)
	}
	if n := m.TouchItem("acct-1", "item-2"); n != 0 {
		t.Fatalf("TouchItem matched a foreign item: %d", n)
	}
	m.clock = func() time.Time { return base.Add(11 * time.Second) }
	m.reap()
	if _, ok := m.Get(s.ID); ok {
		t.Fatal("session survived despite no matching heartbeat")
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

func TestBuildArgsRemux(t *testing.T) {
	args := buildArgs(Spec{Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodRemux})
	joined := strings.Join(args, " ")
	for _, want := range []string{"-i /m/a.mkv", "-c:v copy", "-c:a copy", "-hls_segment_type fmp4", "init.mp4", "stream_%05d.m4s", PlaylistName} {
		if !strings.Contains(joined, want) {
			t.Errorf("remux args missing %q\nargs: %s", want, joined)
		}
	}
	// Remux must not re-encode, scale, or use the %v multi-variant layout (which
	// ffmpeg won't expand in the init filename for a single variant). Without a
	// seek there is nothing to align, so no -noaccurate_seek either.
	for _, bad := range []string{"libx264", "filter_complex", "var_stream_map", "%v", "-tag:v hvc1", "-noaccurate_seek"} {
		if strings.Contains(joined, bad) {
			t.Errorf("remux must not contain %q\nargs: %s", bad, joined)
		}
	}
}

// TestBuildArgsRemuxSeekKeepsAVSync covers ARGY-84: a resumed (StartAt>0) remux
// copies the video, so accurate seek would keep the video from its keyframe but
// drop the audio up to the exact StartAt, leaving audio trailing the video. The
// remux path must use -noaccurate_seek (before -i) so both streams enter at the
// same keyframe; the transcode path re-encodes and must NOT (it seeks exactly).
func TestBuildArgsRemuxSeekKeepsAVSync(t *testing.T) {
	remux := strings.Join(buildArgs(Spec{
		Source: "/m/4k.mkv", OutputDir: "/tmp/out", Method: MethodRemux,
		VideoCodec: CodecHEVC, TranscodeAudio: true, StartAt: 90,
	}), " ")
	if !strings.Contains(remux, "-ss 90.000") {
		t.Errorf("remux seek missing -ss\nargs: %s", remux)
	}
	if !strings.Contains(remux, "-noaccurate_seek") {
		t.Errorf("seeked remux must use -noaccurate_seek to keep A/V in sync\nargs: %s", remux)
	}
	if i, j := strings.Index(remux, "-noaccurate_seek"), strings.Index(remux, "-i "); i < 0 || j < 0 || i > j {
		t.Errorf("-noaccurate_seek must precede -i (it is an input option)\nargs: %s", remux)
	}

	// Transcode re-encodes the video and can seek to the exact frame, so it
	// keeps accurate seek (no -noaccurate_seek).
	transcode := strings.Join(buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode,
		Encoder: EncoderSoftware, SourceHeight: 1080, StartAt: 90,
	}), " ")
	if strings.Contains(transcode, "-noaccurate_seek") {
		t.Errorf("transcode path must keep accurate seek\nargs: %s", transcode)
	}
}

func TestBuildArgsRemuxHEVCWithAudioTranscode(t *testing.T) {
	// The 4K case: copy the HEVC video (with the hvc1 tag) untouched, but
	// re-encode the audio (e.g. TrueHD) to stereo AAC.
	args := buildArgs(Spec{
		Source: "/m/4k.mkv", OutputDir: "/tmp/out", Method: MethodRemux,
		VideoCodec: CodecHEVC, TranscodeAudio: true,
	})
	joined := strings.Join(args, " ")
	for _, want := range []string{"-c:v copy", "-tag:v hvc1", "-c:a aac", "-ac 2"} {
		if !strings.Contains(joined, want) {
			t.Errorf("hevc remux args missing %q\nargs: %s", want, joined)
		}
	}
	// The video is copied, never re-encoded.
	for _, bad := range []string{"hevc_qsv", "libx265", "-c:a copy"} {
		if strings.Contains(joined, bad) {
			t.Errorf("hevc remux must not contain %q\nargs: %s", bad, joined)
		}
	}
}

func TestBuildArgsSingleRung(t *testing.T) {
	// A 480p source → single rung → one media playlist, no master/%v.
	args := buildArgs(Spec{Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode, SourceHeight: 480})
	joined := strings.Join(args, " ")
	for _, want := range []string{"libx264", "scale=-2:480", "init.mp4", "stream_%05d.m4s"} {
		if !strings.Contains(joined, want) {
			t.Errorf("single-rung args missing %q\nargs: %s", want, joined)
		}
	}
	if strings.Contains(joined, "%v") || strings.Contains(joined, "var_stream_map") {
		t.Errorf("single-rung must not use the multi-variant layout\nargs: %s", joined)
	}
}

// dubSub is a two-track (English dub + Japanese) audio set, the ARGY-126 case.
var dubSub = []AudioTrack{
	{Index: 0, Language: "en", Default: true},
	{Index: 1, Language: "ja"},
}

func TestBuildArgsRemuxMultiAudio(t *testing.T) {
	// A remux with 2+ audio tracks maps every stream and emits an EXT-X-MEDIA
	// audio group in a master playlist so clients can switch dub/sub in-session.
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodRemux, AudioTracks: dubSub,
	})
	joined := strings.Join(args, " ")
	for _, want := range []string{
		"-map 0:v:0", "-map 0:a:0", "-map 0:a:1", "-c:v copy", "-c:a copy",
		"-master_pl_name " + PlaylistName, "stream_%v.m3u8", "init_%v.mp4",
		"v:0,agroup:aud",
		"a:0,agroup:aud,language:en,default:yes",
		"a:1,agroup:aud,language:ja",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("multi-audio remux missing %q\nargs: %s", want, joined)
		}
	}
	// `name:` must never appear — it sets the output filename in ffmpeg's
	// var_stream_map (breaking the numeric segment layout / allowlist regex),
	// not the EXT-X-MEDIA NAME.
	if strings.Contains(joined, "name:") {
		t.Errorf("var_stream_map must not use name: (it renames output files)\nargs: %s", joined)
	}
	// Copy-remux must not re-encode the video, and only one rendition is DEFAULT.
	if strings.Contains(joined, "libx264") {
		t.Errorf("multi-audio remux must not re-encode video\nargs: %s", joined)
	}
	if strings.Count(joined, "default:yes") != 1 {
		t.Errorf("exactly one audio rendition must be DEFAULT\nargs: %s", joined)
	}
	// A -b:v hint is required so ffmpeg writes the video EXT-X-STREAM-INF for the
	// copied stream (BANDWIDTH is otherwise unknown and the variant is dropped).
	if !strings.Contains(joined, "-b:v ") {
		t.Errorf("multi-audio remux needs a -b:v hint for the master STREAM-INF\nargs: %s", joined)
	}
}

func TestBuildArgsLadderMultiAudio(t *testing.T) {
	// A transcode ladder with 2+ audio tracks decouples audio from the video
	// rungs: each track is mapped once (not once per rung) and every video
	// variant references the shared audio group.
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Encoder: EncoderSoftware,
		SourceHeight: 1080, AudioTracks: dubSub,
	})
	joined := strings.Join(args, " ")
	for _, want := range []string{
		"split=3", "-map 0:a:0", "-map 0:a:1",
		"v:0,agroup:aud v:1,agroup:aud v:2,agroup:aud",
		"a:0,agroup:aud,language:en,default:yes",
		"a:1,agroup:aud,language:ja",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("multi-audio ladder missing %q\nargs: %s", want, joined)
		}
	}
	// Audio is transcoded to AAC on the ladder path, and mapped exactly once per
	// track (not the single-audio "once per rung" pairing).
	if strings.Count(joined, "-map 0:a:") != 2 {
		t.Errorf("each of 2 audio tracks must map exactly once\nargs: %s", joined)
	}
	if !strings.Contains(joined, "-c:a aac") {
		t.Errorf("ladder audio must be transcoded to AAC\nargs: %s", joined)
	}
	// The old paired var_stream_map form must not appear alongside the group.
	if strings.Contains(joined, "v:0,a:0") {
		t.Errorf("multi-audio ladder must not use the paired v:i,a:i map\nargs: %s", joined)
	}
}

func TestBuildArgsSingleAudioTrackUnchanged(t *testing.T) {
	// A lone audio track is not the multi-rendition case: output stays the simple
	// single-variant layout (no master playlist, no audio group).
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodRemux,
		AudioTracks: []AudioTrack{{Index: 0, Language: "en", Default: true}},
	})
	joined := strings.Join(args, " ")
	for _, bad := range []string{"var_stream_map", "agroup", "%v"} {
		if strings.Contains(joined, bad) {
			t.Errorf("single audio track must keep the simple layout, found %q\nargs: %s", bad, joined)
		}
	}
	if !strings.Contains(joined, "-map 0:a:0") {
		t.Errorf("single audio track should map 0:a:0\nargs: %s", joined)
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
		if got := len(rungsForCodec(c.height, CodecH264)); got != c.want {
			t.Errorf("rungsForCodec(%d, h264) = %d rungs, want %d", c.height, got, c.want)
		}
	}
	// Never upscale: a 480p source's top rung is ≤ 480.
	if r := rungsForCodec(480, CodecH264); r[0].height > 480 {
		t.Errorf("rungsForCodec(480, h264) top rung %d upscales", r[0].height)
	}
}

func TestRungsForCodecHEVC(t *testing.T) {
	// HEVC carries a 2160 rung that H.264 lacks: a 4K source gets the full
	// 2160/1080/720 ladder, where H.264 would top out at 1080.
	if got := len(rungsForCodec(2160, CodecHEVC)); got != 3 {
		t.Errorf("rungsForCodec(2160, hevc) = %d rungs, want 3", got)
	}
	if r := rungsForCodec(2160, CodecHEVC); r[0].height != 2160 {
		t.Errorf("rungsForCodec(2160, hevc) top rung = %d, want 2160", r[0].height)
	}
	if r := rungsForCodec(2160, CodecH264); r[0].height != 1080 {
		t.Errorf("rungsForCodec(2160, h264) top rung = %d, want 1080 (no 4K H.264)", r[0].height)
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
