// Package transcode is The Helm: it spawns, tracks, and tears down ffmpeg
// transcode sessions, exposing one source of truth for live playback sessions.
//
// A Manager owns a set of Sessions. Each Session drives one ffmpeg process via a
// Backend (LocalFFmpeg today; a remote-worker backend can satisfy the same
// contract later — see ARGY-57) that writes HLS artifacts into the session's
// output directory. Sessions are keyed deterministically by (account, item,
// start offset, encoder) so repeat requests for the same content join the
// existing session instead of spawning a duplicate ffmpeg. Idle sessions (no
// playlist/segment access for the idle TTL) are killed and their output purged,
// and the Manager kills everything on shutdown — no orphaned ffmpeg processes.
package transcode

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// ErrAtCapacity is returned by Start when the concurrent-session limit is
// reached; callers should surface back-pressure (HTTP 503) to the client.
var ErrAtCapacity = errors.New("transcode: at session capacity")

// State is the lifecycle state of a transcode session.
type State string

// Transcode methods: remux copies codecs into a browser-friendly container;
// transcode re-encodes. The decision engine (library) picks which.
const (
	MethodRemux     = "remux"
	MethodTranscode = "transcode"
)

// Session lifecycle states.
const (
	StateStarting State = "starting"
	StateRunning  State = "running"
	StateComplete State = "complete"
	StateFailed   State = "failed"
	StateStopped  State = "stopped"
)

// Progress is the live encode progress parsed from ffmpeg.
type Progress struct {
	// OutTimeMS is the encoded timeline position in milliseconds.
	OutTimeMS int64 `json:"outTimeMs"`
	// Speed is the encode speed as a multiple of realtime (e.g. 2.5 == 2.5x).
	Speed float64 `json:"speed"`
	// FPS is the current encode frame rate.
	FPS float64 `json:"fps"`
}

// Spec describes a single transcode job handed to a Backend.
type Spec struct {
	SessionID    string
	Source       string // absolute path to the source media file
	OutputDir    string // directory the backend writes HLS artifacts into
	StartAt      float64
	Encoder      string // selected encoder backend (e.g. "software", "qsv")
	SourceHeight int    // source video height; drives the bitrate ladder (0 = unknown)
	Method       string // MethodRemux (copy codecs) or MethodTranscode (re-encode)
	// VideoCodec is the output video codec (CodecH264/CodecHEVC). For a transcode
	// it selects the encoder + ladder; for a remux it names the codec being
	// copied (so HEVC gets the hvc1 fMP4 tag). Empty defaults to H.264.
	VideoCodec string
	// TranscodeAudio, on the remux path, re-encodes audio to stereo AAC instead
	// of copying it (e.g. TrueHD/DTS alongside a copied 4K HEVC video stream).
	TranscodeAudio bool
}

// StartRequest is the caller-facing request to begin (or join) a session.
type StartRequest struct {
	ItemID         string
	AccountID      string
	Source         string
	StartAt        float64 // seek offset in seconds
	Encoder        string
	SourceHeight   int
	Method         string // MethodRemux or MethodTranscode (default transcode)
	VideoCodec     string // output/copied video codec (CodecH264/CodecHEVC)
	TranscodeAudio bool   // remux: re-encode audio to AAC instead of copying
}

// Session is an immutable snapshot of a transcode session's public state,
// suitable for the API and the The Helm dashboard.
type Session struct {
	ID         string    `json:"id"`
	ItemID     string    `json:"itemId"`
	AccountID  string    `json:"-"`
	Encoder    string    `json:"encoder"`
	Method     string    `json:"method"`
	State      State     `json:"state"`
	StartAt    float64   `json:"startAt"`
	OutputDir  string    `json:"-"`
	Err        string    `json:"error,omitempty"`
	StartedAt  time.Time `json:"startedAt"`
	LastAccess time.Time `json:"lastAccess"`
	Progress   Progress  `json:"progress"`
}

// Backend executes a transcode described by a Spec, writing HLS artifacts into
// spec.OutputDir and blocking until the encode finishes, errors, or ctx is
// cancelled. onProgress is called as encode progress is observed.
type Backend interface {
	Name() string
	Run(ctx context.Context, spec Spec, onProgress func(Progress)) error
}

// session is the Manager's internal, mutable view of a running transcode.
type session struct {
	id, itemID, accountID, encoder, method, outputDir string
	startAt                                           float64
	startedAt                                         time.Time

	mu         sync.Mutex
	state      State
	errMsg     string
	lastAccess time.Time
	progress   Progress

	cancel context.CancelFunc
	done   chan struct{}
}

func (s *session) snapshot() Session {
	s.mu.Lock()
	defer s.mu.Unlock()
	return Session{
		ID:         s.id,
		ItemID:     s.itemID,
		AccountID:  s.accountID,
		Encoder:    s.encoder,
		Method:     s.method,
		State:      s.state,
		StartAt:    s.startAt,
		OutputDir:  s.outputDir,
		Err:        s.errMsg,
		StartedAt:  s.startedAt,
		LastAccess: s.lastAccess,
		Progress:   s.progress,
	}
}

func (s *session) setState(st State, errMsg string) {
	s.mu.Lock()
	s.state = st
	if errMsg != "" {
		s.errMsg = errMsg
	}
	s.mu.Unlock()
}

// setEncoder updates the backend in use (e.g. after a hardware→software
// fallback) so snapshots report what's actually encoding.
func (s *session) setEncoder(enc string) {
	s.mu.Lock()
	s.encoder = enc
	s.mu.Unlock()
}

func (s *session) touch(now time.Time) {
	s.mu.Lock()
	s.lastAccess = now
	s.mu.Unlock()
}

func (s *session) idleSince(cutoff time.Time) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lastAccess.Before(cutoff)
}

func (s *session) updateProgress(p Progress) {
	s.mu.Lock()
	s.progress = p
	s.mu.Unlock()
}

// Manager owns the live set of transcode sessions.
type Manager struct {
	backend Backend
	workDir string
	idleTTL time.Duration
	maxSess int
	logger  *slog.Logger
	clock   func() time.Time

	mu       sync.Mutex
	sessions map[string]*session
}

// NewManager builds a Manager. workDir is where per-session HLS output lives;
// idleTTL is how long a session may go without a playlist/segment request
// before it's reaped; maxSess caps concurrent sessions.
func NewManager(backend Backend, workDir string, idleTTL time.Duration, maxSess int, logger *slog.Logger) *Manager {
	if idleTTL <= 0 {
		idleTTL = 60 * time.Second
	}
	if maxSess <= 0 {
		maxSess = 4
	}
	return &Manager{
		backend:  backend,
		workDir:  workDir,
		idleTTL:  idleTTL,
		maxSess:  maxSess,
		logger:   logger,
		clock:    time.Now,
		sessions: make(map[string]*session),
	}
}

// sessionID derives a deterministic id so repeat requests for the same content
// (same account, item, start offset bucket, and encoder) join one session.
func sessionID(req StartRequest) string {
	// Codec + method are part of the key so clients that negotiated different
	// outputs (e.g. an HEVC-capable client remuxing 4K vs one transcoding to
	// H.264 1080p) get distinct sessions rather than colliding on one.
	key := fmt.Sprintf("%s|%s|%d|%s|%s|%s", req.AccountID, req.ItemID, int64(req.StartAt),
		req.Encoder, resolveCodec(req.VideoCodec), req.Method)
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:])[:16]
}

// Start begins a new session for the request, or returns the existing one if a
// matching session is already live. Returns ErrAtCapacity at the concurrency
// limit.
func (m *Manager) Start(req StartRequest) (Session, error) {
	id := sessionID(req)

	m.mu.Lock()
	if s, ok := m.sessions[id]; ok {
		m.mu.Unlock()
		s.touch(m.clock())
		return s.snapshot(), nil
	}
	if len(m.sessions) >= m.maxSess {
		m.mu.Unlock()
		return Session{}, ErrAtCapacity
	}
	outputDir := filepath.Join(m.workDir, id)
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		m.mu.Unlock()
		return Session{}, fmt.Errorf("transcode: create output dir: %w", err)
	}
	method := req.Method
	if method != MethodRemux {
		method = MethodTranscode
	}
	now := m.clock()
	ctx, cancel := context.WithCancel(context.Background())
	s := &session{
		id: id, itemID: req.ItemID, accountID: req.AccountID, encoder: req.Encoder, method: method,
		outputDir: outputDir, startAt: req.StartAt, startedAt: now,
		state: StateStarting, lastAccess: now, cancel: cancel, done: make(chan struct{}),
	}
	m.sessions[id] = s
	m.mu.Unlock()

	go m.run(ctx, s, Spec{
		SessionID: id, Source: req.Source, OutputDir: outputDir,
		StartAt: req.StartAt, Encoder: req.Encoder, SourceHeight: req.SourceHeight, Method: method,
		VideoCodec: req.VideoCodec, TranscodeAudio: req.TranscodeAudio,
	})
	return s.snapshot(), nil
}

func (m *Manager) run(ctx context.Context, s *session, spec Spec) {
	defer close(s.done)
	s.setState(StateRunning, "")
	err := m.backend.Run(ctx, spec, s.updateProgress)

	// Hardware encode can fail at startup (driver missing, source codec the GPU
	// can't decode, bad device). If nothing was served yet, fall back to software
	// once so the session still plays. We don't retry once segments exist — a
	// client may already be mid-stream.
	if err != nil && ctx.Err() == nil && isHardwareEncoder(spec.Encoder) && !producedSegments(spec.OutputDir) {
		m.logger.Warn("transcode: hardware encode failed at startup, retrying on software",
			"id", s.id, "item", s.itemID, "encoder", spec.Encoder, "err", err)
		_ = cleanDir(spec.OutputDir)
		spec.Encoder = EncoderSoftware
		s.setEncoder(EncoderSoftware)
		if spec.Method == MethodTranscode {
			// Software HEVC (libx265) at 4K is impractically slow; drop to the
			// universal H.264 ladder so the session still plays at a sane speed.
			spec.VideoCodec = CodecH264
		}
		err = m.backend.Run(ctx, spec, s.updateProgress)
	}

	switch {
	case ctx.Err() != nil:
		s.setState(StateStopped, "")
	case err != nil:
		s.setState(StateFailed, err.Error())
		m.logger.Error("transcode session failed", "id", s.id, "item", s.itemID, "err", err)
	default:
		s.setState(StateComplete, "")
	}
}

// producedSegments reports whether any media segment was written — i.e. the
// session got far enough that a client may have started playback.
func producedSegments(dir string) bool {
	matches, _ := filepath.Glob(filepath.Join(dir, "*.m4s"))
	return len(matches) > 0
}

// cleanDir empties a session's output dir before a fallback retry so stale
// partial artifacts don't mislead the muxer or clients.
func cleanDir(dir string) error {
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	return os.MkdirAll(dir, 0o755)
}

// Get returns a snapshot of the session, or ok=false if unknown.
func (m *Manager) Get(id string) (Session, bool) {
	m.mu.Lock()
	s, ok := m.sessions[id]
	m.mu.Unlock()
	if !ok {
		return Session{}, false
	}
	return s.snapshot(), true
}

// Touch marks a session as recently accessed (called on playlist/segment
// requests) so the idle reaper leaves it alone. Returns false if unknown.
func (m *Manager) Touch(id string) bool {
	m.mu.Lock()
	s, ok := m.sessions[id]
	m.mu.Unlock()
	if !ok {
		return false
	}
	s.touch(m.clock())
	return true
}

// Stop cancels a session's ffmpeg process, waits for it to exit (no zombies),
// and purges its output. Returns false if the session is unknown.
func (m *Manager) Stop(id string) bool {
	m.mu.Lock()
	s, ok := m.sessions[id]
	m.mu.Unlock()
	if !ok {
		return false
	}
	m.kill(s)
	return true
}

// LiveIDs returns the set of session IDs currently tracked — i.e. the output
// directories Ballast must not purge. Satisfies ballast.Live.
func (m *Manager) LiveIDs() map[string]bool {
	m.mu.Lock()
	out := make(map[string]bool, len(m.sessions))
	for id := range m.sessions {
		out[id] = true
	}
	m.mu.Unlock()
	return out
}

// List returns snapshots of all live sessions for the The Helm dashboard.
func (m *Manager) List() []Session {
	m.mu.Lock()
	out := make([]Session, 0, len(m.sessions))
	for _, s := range m.sessions {
		out = append(out, s.snapshot())
	}
	m.mu.Unlock()
	return out
}

// kill cancels, waits for the process to exit, then removes the session and its
// output directory.
func (m *Manager) kill(s *session) {
	s.cancel()
	<-s.done
	m.mu.Lock()
	delete(m.sessions, s.id)
	m.mu.Unlock()
	if err := os.RemoveAll(s.outputDir); err != nil {
		m.logger.Warn("transcode: purge output failed", "id", s.id, "err", err)
	}
}

// Run drives the idle reaper until ctx is cancelled, then shuts down every live
// session. Call it in a goroutine from main.
func (m *Manager) Run(ctx context.Context) {
	interval := m.idleTTL / 2
	if interval < time.Second {
		interval = time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			m.shutdown()
			return
		case <-ticker.C:
			m.reap()
		}
	}
}

func (m *Manager) reap() {
	cutoff := m.clock().Add(-m.idleTTL)
	m.mu.Lock()
	var stale []*session
	for _, s := range m.sessions {
		if s.idleSince(cutoff) {
			stale = append(stale, s)
		}
	}
	m.mu.Unlock()
	for _, s := range stale {
		m.logger.Info("transcode: reaping idle session", "id", s.id, "item", s.itemID)
		m.kill(s)
	}
}

func (m *Manager) shutdown() {
	m.mu.Lock()
	all := make([]*session, 0, len(m.sessions))
	for _, s := range m.sessions {
		all = append(all, s)
	}
	m.mu.Unlock()
	for _, s := range all {
		m.kill(s)
	}
}
