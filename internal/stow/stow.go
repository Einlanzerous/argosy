// Package stow owns the packaging half of offline downloads (ARGY-49).
//
// Stow lets a device pack an item away for viewing with no server reachable —
// a flight, a commute. What the device downloads is decided per item by the
// library layer (planStow): a source that a phone can already play, at a size a
// phone can hold, is handed over untouched through the existing range-capable
// /items/{id}/stream and never reaches this package. Everything else is
// re-encoded here into one progressive MP4.
//
// A packaging job is deliberately not modelled like a transcode session. A
// session is ephemeral, memory-resident, and reaped the moment a client stops
// pulling segments; a package has no client attached at all for the length of a
// 40-minute encode, and its artifact has to survive until the device gets around
// to downloading it. So jobs live in Postgres, run under a context detached from
// the request that created them, and are reclaimed on a retention clock rather
// than an idle one.
package stow

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// State is the lifecycle state of a packaging job.
type State string

// Job lifecycle states. A job is created pending, becomes packaging once it wins
// a slot from the concurrency limit, and ends ready or failed.
const (
	StatePending   State = "pending"
	StatePackaging State = "packaging"
	StateReady     State = "ready"
	StateFailed    State = "failed"
)

// DefaultRetention is how long a finished package is kept on the server. The
// normal path is much shorter — the device deletes the job as soon as it has the
// bytes — so this only catches downloads that were never collected.
const DefaultRetention = 7 * 24 * time.Hour

// failedRetention is how long a failed job's row is kept. Long enough for the
// client to poll and show the user why, short enough not to accumulate.
const failedRetention = time.Hour

// Job is a snapshot of a packaging job.
type Job struct {
	ID              string
	AccountID       string
	ItemID          string
	State           State
	Encoder         string
	OutputBytes     int64
	DurationSeconds float64
	ProgressMS      int64
	Err             string
	CreatedAt       time.Time
	UpdatedAt       time.Time
	ReadyAt         *time.Time
}

// Request asks for an item to be packaged for offline viewing.
type Request struct {
	// AccountID is the requesting household account — jobs are scoped to it, so
	// one member can neither see nor cancel another's.
	AccountID string
	ItemID    string
	// Source is the absolute, already traversal-checked path to the media file.
	Source          string
	SourceHeight    int
	DurationSeconds float64
	AudioTracks     []transcode.AudioTrack
}

// Packager runs one packaging encode. transcode.LocalFFmpeg satisfies it; a
// remote worker backend (ARGY-57) could too.
type Packager interface {
	Package(ctx context.Context, spec transcode.PackageSpec, onProgress func(transcode.Progress)) error
}

// Manager owns the packaging queue and the artifact directory.
type Manager struct {
	pool      *pgxpool.Pool
	backend   Packager
	workDir   string
	encoder   string
	retention time.Duration
	logger    *slog.Logger
	clock     func() time.Time

	// sem caps concurrent encodes. Packaging competes with live playback for the
	// same CPU/GPU, and nobody is waiting on it in realtime, so the default is
	// deliberately small.
	sem chan struct{}

	mu      sync.Mutex
	running map[string]context.CancelFunc
}

// New builds a Manager. workDir is where per-job artifacts live (one directory
// per job id, which is also what Ballast keys on); maxJobs caps concurrent
// encodes (<=0 means 1); retention is how long a finished package is kept
// (<=0 means DefaultRetention).
func New(pool *pgxpool.Pool, backend Packager, workDir, encoder string, maxJobs int, retention time.Duration, logger *slog.Logger) *Manager {
	if maxJobs <= 0 {
		maxJobs = 1
	}
	if retention <= 0 {
		retention = DefaultRetention
	}
	return &Manager{
		pool:      pool,
		backend:   backend,
		workDir:   workDir,
		encoder:   encoder,
		retention: retention,
		logger:    logger,
		clock:     time.Now,
		sem:       make(chan struct{}, maxJobs),
		running:   make(map[string]context.CancelFunc),
	}
}

// ArtifactPath is where a job's packaged MP4 lives once it is ready.
func (m *Manager) ArtifactPath(jobID string) string {
	return filepath.Join(m.workDir, jobID, transcode.PackageName)
}

const jobColumns = `id, account_id, item_id, state, encoder, output_bytes,
	duration_seconds, progress_ms, error, created_at, updated_at, ready_at`

func scanJob(row pgx.Row) (Job, error) {
	var j Job
	err := row.Scan(&j.ID, &j.AccountID, &j.ItemID, &j.State, &j.Encoder, &j.OutputBytes,
		&j.DurationSeconds, &j.ProgressMS, &j.Err, &j.CreatedAt, &j.UpdatedAt, &j.ReadyAt)
	return j, err
}

// Request queues an item for packaging, or returns the job already covering it.
// A previously failed job is reset and retried rather than duplicated.
func (m *Manager) Request(ctx context.Context, req Request) (Job, error) {
	// A failed job is the only state a new request rewrites: pending and
	// packaging are already on their way, and ready is the answer.
	job, err := scanJob(m.pool.QueryRow(ctx, `
		INSERT INTO stow_jobs (account_id, item_id, state, encoder, duration_seconds)
		VALUES ($1, $2, 'pending', $3, $4)
		ON CONFLICT (account_id, item_id) DO UPDATE SET
			state       = CASE WHEN stow_jobs.state = 'failed' THEN 'pending' ELSE stow_jobs.state END,
			error       = CASE WHEN stow_jobs.state = 'failed' THEN ''        ELSE stow_jobs.error END,
			progress_ms = CASE WHEN stow_jobs.state = 'failed' THEN 0         ELSE stow_jobs.progress_ms END,
			encoder          = EXCLUDED.encoder,
			duration_seconds = EXCLUDED.duration_seconds,
			updated_at       = now()
		RETURNING `+jobColumns,
		req.AccountID, req.ItemID, m.encoder, req.DurationSeconds))
	if err != nil {
		return Job{}, fmt.Errorf("stow: queue job: %w", err)
	}
	if job.State == StatePending {
		m.ensureWorker(job.ID, req)
	}
	return job, nil
}

// ensureWorker starts the encode goroutine for a pending job unless one is
// already attached to that id.
func (m *Manager) ensureWorker(jobID string, req Request) {
	// The job must outlive the HTTP request that created it — a 40-minute encode
	// has no client attached, and cancelling it when the caller disconnects would
	// mean a stow only ever completes if the app stays open. Same reasoning as
	// the detached audit write in internal/auth/audit.go, for the same reason:
	// the work is not the request.
	ctx, cancel := context.WithCancel(context.Background())
	m.mu.Lock()
	if _, busy := m.running[jobID]; busy {
		m.mu.Unlock()
		cancel()
		return
	}
	m.running[jobID] = cancel
	m.mu.Unlock()

	go m.work(ctx, jobID, req)
}

func (m *Manager) work(ctx context.Context, jobID string, req Request) {
	defer func() {
		m.mu.Lock()
		delete(m.running, jobID)
		m.mu.Unlock()
	}()

	// Wait for a packaging slot. A queued job stays visibly `pending` while it
	// waits, so the client can say "queued" rather than showing a stalled 0%.
	select {
	case m.sem <- struct{}{}:
		defer func() { <-m.sem }()
	case <-ctx.Done():
		return
	}
	if ctx.Err() != nil {
		return
	}

	outputDir := filepath.Join(m.workDir, jobID)
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		m.finish(jobID, fmt.Errorf("create output dir: %w", err))
		return
	}
	if err := m.setState(jobID, StatePackaging, ""); err != nil {
		m.logger.Error("stow: mark packaging failed", "job", jobID, "err", err)
	}

	spec := transcode.PackageSpec{
		Source:       req.Source,
		OutputDir:    outputDir,
		Encoder:      m.encoder,
		SourceHeight: req.SourceHeight,
		AudioTracks:  req.AudioTracks,
	}
	m.logger.Info("stow: packaging", "job", jobID, "item", req.ItemID, "encoder", m.encoder,
		"height", req.SourceHeight, "audioTracks", len(req.AudioTracks))

	err := m.backend.Package(ctx, spec, m.progressSink(jobID))

	// Hardware encode can fail at startup (driver missing, a source the GPU can't
	// decode). Retry once on software, mirroring the session path — a stow that
	// silently fails is worse than one that takes longer.
	if err != nil && ctx.Err() == nil && m.encoder != transcode.EncoderSoftware && !hasOutput(outputDir) {
		m.logger.Warn("stow: hardware package failed at startup, retrying on software",
			"job", jobID, "encoder", m.encoder, "err", err)
		spec.Encoder = transcode.EncoderSoftware
		err = m.backend.Package(ctx, spec, m.progressSink(jobID))
	}

	if ctx.Err() != nil {
		// Cancelled: Delete owns the row and the directory, so leave both alone.
		return
	}
	m.finish(jobID, err)
}

// finish records a job's terminal state, purging the artifact directory when the
// encode failed so a partial MP4 is never downloadable.
func (m *Manager) finish(jobID string, err error) {
	if err != nil {
		m.logger.Error("stow: packaging failed", "job", jobID, "err", err)
		if rmErr := os.RemoveAll(filepath.Join(m.workDir, jobID)); rmErr != nil {
			m.logger.Warn("stow: purge failed package", "job", jobID, "err", rmErr)
		}
		if sErr := m.setState(jobID, StateFailed, err.Error()); sErr != nil {
			m.logger.Error("stow: mark failed", "job", jobID, "err", sErr)
		}
		return
	}
	var size int64
	if fi, statErr := os.Stat(m.ArtifactPath(jobID)); statErr == nil {
		size = fi.Size()
	}
	if _, dbErr := m.pool.Exec(context.Background(), `
		UPDATE stow_jobs SET state = 'ready', output_bytes = $2, error = '',
		       ready_at = now(), updated_at = now()
		WHERE id = $1`, jobID, size); dbErr != nil {
		m.logger.Error("stow: mark ready", "job", jobID, "err", dbErr)
		return
	}
	m.logger.Info("stow: package ready", "job", jobID, "bytes", size)
}

// progressSink throttles ffmpeg's progress ticks (a few per second) down to a
// DB write every couple of seconds — the client polls far slower than ffmpeg
// reports, so writing every tick would be pure churn. Only the encoded position
// is stored; the client renders the percentage against duration_seconds, which
// was written when the job was queued.
func (m *Manager) progressSink(jobID string) func(transcode.Progress) {
	var mu sync.Mutex
	var last time.Time
	return func(p transcode.Progress) {
		mu.Lock()
		now := m.clock()
		if now.Sub(last) < 2*time.Second {
			mu.Unlock()
			return
		}
		last = now
		mu.Unlock()

		if _, err := m.pool.Exec(context.Background(),
			`UPDATE stow_jobs SET progress_ms = $2, updated_at = now() WHERE id = $1`,
			jobID, p.OutTimeMS); err != nil {
			m.logger.Warn("stow: progress update failed", "job", jobID, "err", err)
		}
	}
}

func (m *Manager) setState(jobID string, st State, errMsg string) error {
	_, err := m.pool.Exec(context.Background(),
		`UPDATE stow_jobs SET state = $2, error = $3, updated_at = now() WHERE id = $1`,
		jobID, st, errMsg)
	return err
}

// hasOutput reports whether the encode wrote anything at all — the signal for
// whether a hardware failure happened at startup (retryable on software) or
// partway through (not worth restarting from zero).
func hasOutput(dir string) bool {
	fi, err := os.Stat(filepath.Join(dir, transcode.PackageName))
	return err == nil && fi.Size() > 0
}

// Get returns one job scoped to the requesting account. ok is false when the id
// is unknown *or* belongs to another account — a member must not be able to
// probe for another's jobs.
func (m *Manager) Get(ctx context.Context, accountID, jobID string) (Job, bool, error) {
	job, err := scanJob(m.pool.QueryRow(ctx,
		`SELECT `+jobColumns+` FROM stow_jobs WHERE id = $1 AND account_id = $2`, jobID, accountID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Job{}, false, nil
	}
	if err != nil {
		return Job{}, false, err
	}
	return job, true, nil
}

// ByItem returns the account's job for an item, if it has one.
func (m *Manager) ByItem(ctx context.Context, accountID, itemID string) (Job, bool, error) {
	job, err := scanJob(m.pool.QueryRow(ctx,
		`SELECT `+jobColumns+` FROM stow_jobs WHERE account_id = $1 AND item_id = $2`, accountID, itemID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Job{}, false, nil
	}
	if err != nil {
		return Job{}, false, err
	}
	return job, true, nil
}

// List returns the account's jobs, newest first.
func (m *Manager) List(ctx context.Context, accountID string) ([]Job, error) {
	rows, err := m.pool.Query(ctx,
		`SELECT `+jobColumns+` FROM stow_jobs WHERE account_id = $1 ORDER BY created_at DESC`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Job{}
	for rows.Next() {
		j, err := scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

// Delete cancels a job if it is still encoding, purges its artifact, and removes
// the row. It is the client's "cancel" and its "I have the bytes, clean up"
// alike. ok is false when the id is unknown or belongs to another account.
func (m *Manager) Delete(ctx context.Context, accountID, jobID string) (bool, error) {
	tag, err := m.pool.Exec(ctx, `DELETE FROM stow_jobs WHERE id = $1 AND account_id = $2`, jobID, accountID)
	if err != nil {
		return false, err
	}
	if tag.RowsAffected() == 0 {
		return false, nil
	}
	// Cancel after the row is gone: the worker checks ctx and bows out without
	// touching a row that no longer exists.
	m.mu.Lock()
	cancel := m.running[jobID]
	m.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if err := os.RemoveAll(filepath.Join(m.workDir, jobID)); err != nil {
		m.logger.Warn("stow: purge artifact failed", "job", jobID, "err", err)
	}
	return true, nil
}

// LiveIDs reports the job directories Ballast must not reclaim: everything that
// is queued, encoding, or waiting to be collected. A failed job holds no
// artifact, so its directory is fair game. Returns nil on a query failure, which
// the sweeper reads as "unknown" and skips — never as "purge everything".
func (m *Manager) LiveIDs() map[string]bool {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	rows, err := m.pool.Query(ctx,
		`SELECT id FROM stow_jobs WHERE state IN ('pending', 'packaging', 'ready')`)
	if err != nil {
		m.logger.Warn("stow sweep: listing live jobs failed", "err", err)
		return nil
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			m.logger.Warn("stow sweep: scanning job id failed", "err", err)
			return nil
		}
		out[id] = true
	}
	if err := rows.Err(); err != nil {
		m.logger.Warn("stow sweep: listing live jobs failed", "err", err)
		return nil
	}
	return out
}

// ResetInterrupted fails every job left mid-flight by a previous process. The
// spec an encode needs (source path, height, audio layout) is derived from the
// catalog by the caller and deliberately not duplicated into the row, so a job
// cannot be resumed from the row alone — and re-deriving it at boot would mean
// storing a file path that a rescan is free to invalidate. Failing the job puts
// a retry one tap away instead, and the partial artifact becomes an orphan that
// Ballast reclaims.
func (m *Manager) ResetInterrupted(ctx context.Context) error {
	tag, err := m.pool.Exec(ctx, `
		UPDATE stow_jobs SET state = 'failed', progress_ms = 0, updated_at = now(),
		       error = 'interrupted by a server restart — stow it again to retry'
		WHERE state IN ('pending', 'packaging')`)
	if err != nil {
		return err
	}
	if n := tag.RowsAffected(); n > 0 {
		m.logger.Info("stow: failed jobs interrupted by restart", "count", n)
	}
	return nil
}

// Run drives the retention sweep until ctx is cancelled.
func (m *Manager) Run(ctx context.Context) {
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.sweep(ctx)
		}
	}
}

// sweep drops packages nobody collected and failed jobs nobody looked at. The
// artifact directories are left to Ballast, which reclaims them once these rows
// stop reporting them live.
func (m *Manager) sweep(ctx context.Context) {
	tag, err := m.pool.Exec(ctx, `
		DELETE FROM stow_jobs
		WHERE (state = 'ready'  AND ready_at  < now() - $1::interval)
		   OR (state = 'failed' AND updated_at < now() - $2::interval)`,
		m.retention.String(), failedRetention.String())
	if err != nil {
		m.logger.Warn("stow: retention sweep failed", "err", err)
		return
	}
	if n := tag.RowsAffected(); n > 0 {
		m.logger.Info("stow: retention sweep removed jobs", "count", n)
	}
}
