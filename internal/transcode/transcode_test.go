package transcode

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
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

// oneTrack is a lone English audio stream — the single-audio case.
var oneTrack = []AudioTrack{{Index: 0, Language: "en", Default: true}}

func TestBuildArgsSingleAudioTrackUnchanged(t *testing.T) {
	// A lone audio track is not the multi-rendition case: output stays the simple
	// single-variant layout (no master playlist, no audio group).
	//
	// The zero-value VideoCodec resolves to H.264, and that matters here: an HEVC
	// copy takes the master path regardless of track count so it can declare
	// CODECS (ARGY-218). This test pins the H.264 side of that split — the common
	// single-audio remux, which must keep the cheaper layout.
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodRemux,
		AudioTracks: oneTrack,
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

func TestBuildArgsRemuxSingleAudioHEVCEmitsMaster(t *testing.T) {
	// ARGY-218: a copied HEVC stream must land in a master playlist so the output
	// declares CODECS. A media playlist declares none, and hls.js cannot recover
	// an HEVC codec string from the init segment — it asks for a bare "hvc1"
	// SourceBuffer, which browsers reject, killing playback on segment 0.
	args := buildArgs(Spec{
		Source: "/m/4k.mkv", OutputDir: "/tmp/out", Method: MethodRemux,
		VideoCodec: CodecHEVC, TranscodeAudio: true, SourceHeight: 2160,
		AudioTracks: oneTrack,
	})
	joined := strings.Join(args, " ")
	for _, want := range []string{
		"-var_stream_map", "agroup", "-master_pl_name index.m3u8",
		"init_%v.mp4", "stream_%v_%05d.m4s",
		// A copied stream carries no encoder bitrate, so without this hint ffmpeg
		// cannot compute BANDWIDTH and omits the video EXT-X-STREAM-INF — leaving
		// a master with no video variant, and so no CODECS either.
		"-b:v 20M",
		// Still a copy: the point is the manifest, not a re-encode.
		"-c:v copy", "-tag:v hvc1",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("single-audio HEVC remux missing %q\nargs: %s", want, joined)
		}
	}
	for _, bad := range []string{"libx265", "hevc_qsv", "hevc_vaapi"} {
		if strings.Contains(joined, bad) {
			t.Errorf("single-audio HEVC remux must not re-encode, found %q\nargs: %s", bad, joined)
		}
	}
}

func TestBuildArgsRemuxHEVCWithoutEnumeratedTracksStaysSingle(t *testing.T) {
	// audioGroupVSM builds the audio group out of AudioTracks; with none it would
	// emit a video variant pointing at an empty group. A source whose ffprobe JSON
	// was never stored lands here, so it keeps the pre-ARGY-218 single-variant
	// output rather than a master that references nothing.
	args := buildArgs(Spec{
		Source: "/m/4k.mkv", OutputDir: "/tmp/out", Method: MethodRemux,
		VideoCodec: CodecHEVC, TranscodeAudio: true, SourceHeight: 2160,
	})
	joined := strings.Join(args, " ")
	for _, bad := range []string{"var_stream_map", "agroup", "%v"} {
		if strings.Contains(joined, bad) {
			t.Errorf("HEVC remux with no enumerated tracks must stay single-variant, found %q\nargs: %s", bad, joined)
		}
	}
}

func TestBuildArgsSingleRungHEVCEmitsMaster(t *testing.T) {
	// The same CODECS requirement applies to an HEVC *encode* that collapses to
	// one rung. planPlayback only picks HEVC above 1080p and every such height
	// yields 2+ rungs, so this does not arise today — the branch exists to keep
	// both single-variant exits consistent, and this pins it.
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode,
		Encoder: EncoderSoftware, VideoCodec: CodecHEVC, SourceHeight: 720,
		AudioTracks: oneTrack,
	})
	joined := strings.Join(args, " ")
	if len(rungsForCodec(720, CodecHEVC)) != 1 {
		t.Fatalf("test premise broken: 720p HEVC no longer collapses to one rung")
	}
	for _, want := range []string{"-var_stream_map", "agroup", "-master_pl_name index.m3u8"} {
		if !strings.Contains(joined, want) {
			t.Errorf("single-rung HEVC encode missing %q\nargs: %s", want, joined)
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

// segmentBackend writes one media segment into the output dir, the way a real
// encode would, then returns. producedSegments sees it.
type segmentBackend struct{}

func (segmentBackend) Name() string { return "segment" }
func (segmentBackend) Run(_ context.Context, spec Spec, _ func(Progress)) error {
	return os.WriteFile(filepath.Join(spec.OutputDir, "stream_0_00000.m4s"), []byte("seg"), 0o644)
}

// TestStalledSessionWarning covers the ARGY-174 signal: encoded output that no
// client ever fetched. It has to stay quiet for sessions that streamed, for
// sessions that never got far enough to have anything to serve, and for
// shutdown — a warning that cries wolf during normal playback is worse than no
// warning, since the whole point is that this failure is otherwise invisible.
func TestStalledSessionWarning(t *testing.T) {
	// waitForSegment gives the backend goroutine time to write before teardown.
	waitForSegment := func(t *testing.T, dir string) {
		t.Helper()
		for i := 0; i < 100; i++ {
			if producedSegments(dir) {
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatal("backend never produced a segment")
	}

	t.Run("manifest fetched, nothing streamed", func(t *testing.T) {
		var buf bytes.Buffer
		m := NewManager(segmentBackend{}, t.TempDir(), time.Minute, 4, slog.New(slog.NewTextHandler(&buf, nil)))
		s, err := m.Start(newReq("item-stalled"))
		if err != nil {
			t.Fatal(err)
		}
		waitForSegment(t, s.OutputDir)
		m.MarkServed(s.ID, false)
		m.Stop(s.ID)
		if !strings.Contains(buf.String(), "never served one") {
			t.Errorf("no warning for a session that served a manifest and nothing else:\n%s", buf.String())
		}
		if !strings.Contains(buf.String(), "playlistServed=true") {
			t.Errorf("warning should record that the manifest went out:\n%s", buf.String())
		}
	})

	t.Run("nothing served at all", func(t *testing.T) {
		// The client never came back for anything. Still wasted encode, still
		// worth saying — the earlier predicate was silent here.
		var buf bytes.Buffer
		m := NewManager(segmentBackend{}, t.TempDir(), time.Minute, 4, slog.New(slog.NewTextHandler(&buf, nil)))
		s, err := m.Start(newReq("item-silent"))
		if err != nil {
			t.Fatal(err)
		}
		waitForSegment(t, s.OutputDir)
		m.Stop(s.ID)
		if !strings.Contains(buf.String(), "never served one") {
			t.Errorf("no warning for a session that served nothing:\n%s", buf.String())
		}
		if !strings.Contains(buf.String(), "playlistServed=false") {
			t.Errorf("warning should distinguish 'never fetched the manifest':\n%s", buf.String())
		}
	})

	t.Run("streamed", func(t *testing.T) {
		var buf bytes.Buffer
		m := NewManager(segmentBackend{}, t.TempDir(), time.Minute, 4, slog.New(slog.NewTextHandler(&buf, nil)))
		s, err := m.Start(newReq("item-played"))
		if err != nil {
			t.Fatal(err)
		}
		waitForSegment(t, s.OutputDir)
		m.MarkServed(s.ID, false)
		m.MarkServed(s.ID, true)
		m.Stop(s.ID)
		if strings.Contains(buf.String(), "never served one") {
			t.Errorf("warned about a session that streamed:\n%s", buf.String())
		}
	})

	t.Run("no segments produced", func(t *testing.T) {
		// Abandoned before the encode got anywhere. Nothing to serve, so nothing
		// to blame the client for.
		var buf bytes.Buffer
		be := &blockingBackend{}
		m := NewManager(be, t.TempDir(), time.Minute, 4, slog.New(slog.NewTextHandler(&buf, nil)))
		s, err := m.Start(newReq("item-early-exit"))
		if err != nil {
			t.Fatal(err)
		}
		m.MarkServed(s.ID, false)
		m.Stop(s.ID)
		if strings.Contains(buf.String(), "never served one") {
			t.Errorf("warned about a session with no encoded output:\n%s", buf.String())
		}
	})

	t.Run("shutdown", func(t *testing.T) {
		// Every live session is torn down mid-stream here; "no segment served"
		// says nothing about any client.
		var buf bytes.Buffer
		m := NewManager(segmentBackend{}, t.TempDir(), time.Minute, 4, slog.New(slog.NewTextHandler(&buf, nil)))
		s, err := m.Start(newReq("item-shutdown"))
		if err != nil {
			t.Fatal(err)
		}
		waitForSegment(t, s.OutputDir)
		m.MarkServed(s.ID, false)
		m.shutdown()
		if strings.Contains(buf.String(), "never served one") {
			t.Errorf("warned during shutdown:\n%s", buf.String())
		}
	})
}

// TestSnapshotReportsServedArtifacts keeps the served flags observable while a
// session is live, not only in the teardown log line.
func TestSnapshotReportsServedArtifacts(t *testing.T) {
	m := NewManager(&blockingBackend{}, t.TempDir(), time.Minute, 4, discardLogger())
	s, err := m.Start(newReq("item-snap"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { m.Stop(s.ID) })

	if snap, _ := m.Get(s.ID); snap.ServedPlaylist || snap.ServedSegment {
		t.Fatalf("fresh session already marked served: %+v", snap)
	}
	m.MarkServed(s.ID, false)
	if snap, _ := m.Get(s.ID); !snap.ServedPlaylist || snap.ServedSegment {
		t.Errorf("after a playlist: ServedPlaylist=%v ServedSegment=%v, want true/false",
			snap.ServedPlaylist, snap.ServedSegment)
	}
	m.MarkServed(s.ID, true)
	if snap, _ := m.Get(s.ID); !snap.ServedSegment {
		t.Error("segment fetch not reflected in the snapshot")
	}
}
