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

	"github.com/Einlanzerous/argosy/internal/fileid"
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

// StaleMessage is what a job reports once its item's file has been replaced
// since the job was made (ARGY-238). An item keeps its id across a replacement,
// so without this a package of the old file would be handed over as the item —
// with sidecar captions the phone fetches afterwards from the new file, which
// need not line up. Failing asks for one more tap instead: Retry re-requests,
// and a request for a job whose source changed re-packages the new file.
const StaleMessage = "The file changed on the server — stow it again."

// errStale is what a worker finishes with when its source was replaced; finish
// records it on the row as StaleMessage.
var errStale = errors.New("stow: source file replaced since the job was made")

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
	// SourceIdentity is the fileid identity of the file the job was made from.
	SourceIdentity string
	// Stale is set by Get when the item's file no longer matches SourceIdentity.
	// State and Err are then reported as failed with StaleMessage, whatever the
	// row says, so every path the phone polls tells it the same thing.
	Stale bool
}

// Request asks for an item to be packaged for offline viewing.
type Request struct {
	// AccountID is the requesting household account — jobs are scoped to it, so
	// one member can neither see nor cancel another's.
	AccountID string
	ItemID    string
	// Source is the absolute, already traversal-checked path to the media file.
	Source string
	// SourceIdentity is the fileid identity of that file, read in the same query
	// as Source so the two describe one file. Empty is treated as fileid.Unknown.
	SourceIdentity  string
	SourceHeight    int
	DurationSeconds float64
	AudioTracks     []transcode.AudioTrack
}

func (r Request) identity() string {
	if r.SourceIdentity == "" {
		return fileid.Unknown
	}
	return r.SourceIdentity
}

// Packager runs one packaging encode. transcode.LocalFFmpeg satisfies it; a
// remote worker backend (ARGY-57) could too.
type Packager interface {
	Package(ctx context.Context, spec transcode.PackageSpec, onProgress func(transcode.Progress)) error
}

// worker is the goroutine encoding one job. done closes once it has returned,
// which is what lets a request that resets the job wait for it: the replacement
// worker writes its package at the same path.
type worker struct {
	cancel context.CancelFunc
	done   chan struct{}
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
	running map[string]*worker
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
		running:   make(map[string]*worker),
	}
}

// ArtifactPath is where a job's packaged MP4 lives once it is ready.
func (m *Manager) ArtifactPath(jobID string) string {
	return filepath.Join(m.workDir, jobID, transcode.PackageName)
}

// jobColumns is qualified with the sj alias every query here gives stow_jobs,
// because Get joins media_items for the item's current identity.
const jobColumns = `sj.id, sj.account_id, sj.item_id, sj.state, sj.encoder, sj.output_bytes,
	sj.duration_seconds, sj.progress_ms, sj.error, sj.created_at, sj.updated_at, sj.ready_at,
	sj.source_identity`

func scanJob(row pgx.Row) (Job, error) {
	var j Job
	err := row.Scan(&j.ID, &j.AccountID, &j.ItemID, &j.State, &j.Encoder, &j.OutputBytes,
		&j.DurationSeconds, &j.ProgressMS, &j.Err, &j.CreatedAt, &j.UpdatedAt, &j.ReadyAt,
		&j.SourceIdentity)
	return j, err
}

// Request queues an item for packaging, or returns the job already covering it.
// A previously failed job is reset and retried rather than duplicated, and so is
// one made from a file the library has since replaced.
func (m *Manager) Request(ctx context.Context, req Request) (Job, error) {
	identity := req.identity()

	// A job made from a replaced file is not the answer to this request. Its
	// worker is stopped and waited for before the row is reset, because the new
	// worker writes its package where the old one was writing; and its artifact
	// goes, because a stale package.mp4 left in the directory would read as
	// output to the hardware-retry check.
	existing, ok, err := m.ByItem(ctx, req.AccountID, req.ItemID)
	if err != nil {
		return Job{}, fmt.Errorf("stow: load job: %w", err)
	}
	if ok && existing.SourceIdentity != identity {
		m.logger.Info("stow: source changed", "job", existing.ID, "item", req.ItemID,
			"old", existing.SourceIdentity, "new", identity, "caught", "request")
		m.stopWorker(existing.ID)
		if err := os.RemoveAll(filepath.Join(m.workDir, existing.ID)); err != nil {
			m.logger.Warn("stow: purge stale package failed", "job", existing.ID, "err", err)
		}
	}

	// A failed job, or one whose source changed, is the only kind a new request
	// rewrites: pending and packaging are already on their way, and ready is the
	// answer.
	job, err := scanJob(m.pool.QueryRow(ctx, `
		INSERT INTO stow_jobs AS sj (account_id, item_id, state, encoder, duration_seconds, source_identity)
		VALUES ($1, $2, 'pending', $3, $4, $5)
		ON CONFLICT (account_id, item_id) DO UPDATE SET
			state        = CASE WHEN sj.state = 'failed' OR sj.source_identity <> EXCLUDED.source_identity
			                    THEN 'pending' ELSE sj.state END,
			error        = CASE WHEN sj.state = 'failed' OR sj.source_identity <> EXCLUDED.source_identity
			                    THEN '' ELSE sj.error END,
			progress_ms  = CASE WHEN sj.state = 'failed' OR sj.source_identity <> EXCLUDED.source_identity
			                    THEN 0 ELSE sj.progress_ms END,
			output_bytes = CASE WHEN sj.source_identity <> EXCLUDED.source_identity THEN 0 ELSE sj.output_bytes END,
			ready_at     = CASE WHEN sj.source_identity <> EXCLUDED.source_identity THEN NULL ELSE sj.ready_at END,
			source_identity  = EXCLUDED.source_identity,
			encoder          = EXCLUDED.encoder,
			duration_seconds = EXCLUDED.duration_seconds,
			updated_at       = now()
		RETURNING `+jobColumns,
		req.AccountID, req.ItemID, m.encoder, req.DurationSeconds, identity))
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
	w := &worker{cancel: cancel, done: make(chan struct{})}
	m.mu.Lock()
	if _, busy := m.running[jobID]; busy {
		m.mu.Unlock()
		cancel()
		return
	}
	m.running[jobID] = w
	m.mu.Unlock()

	go m.work(ctx, w, jobID, req)
}

// stopWorker cancels the worker attached to a job, if any, and waits for it to
// return.
func (m *Manager) stopWorker(jobID string) {
	m.mu.Lock()
	w := m.running[jobID]
	m.mu.Unlock()
	if w == nil {
		return
	}
	w.cancel()
	<-w.done
}

func (m *Manager) work(ctx context.Context, w *worker, jobID string, req Request) {
	identity := req.identity()
	defer func() {
		m.mu.Lock()
		// Only our own entry: a request may already have attached a successor.
		if m.running[jobID] == w {
			delete(m.running, jobID)
		}
		m.mu.Unlock()
		close(w.done)
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

	// The file may have been replaced while this job queued, in which case
	// req.Source names a path that is already gone. Say what happened rather
	// than let ffmpeg fail on it.
	if m.sourceChanged(req.ItemID, identity, jobID, "work-before") {
		m.finish(jobID, identity, errStale)
		return
	}

	outputDir := filepath.Join(m.workDir, jobID)
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		m.finish(jobID, identity, fmt.Errorf("create output dir: %w", err))
		return
	}
	if err := m.setState(jobID, identity, StatePackaging, ""); err != nil {
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

	err := m.backend.Package(ctx, spec, m.progressSink(jobID, identity))

	// Hardware encode can fail at startup (driver missing, a source the GPU can't
	// decode). Retry once on software, mirroring the session path — a stow that
	// silently fails is worse than one that takes longer.
	if err != nil && ctx.Err() == nil && m.encoder != transcode.EncoderSoftware && !hasOutput(outputDir) {
		m.logger.Warn("stow: hardware package failed at startup, retrying on software",
			"job", jobID, "encoder", m.encoder, "err", err)
		spec.Encoder = transcode.EncoderSoftware
		err = m.backend.Package(ctx, spec, m.progressSink(jobID, identity))
	}

	if ctx.Err() != nil {
		// Cancelled: Delete (or a request resetting the job) owns the row and the
		// directory, so leave both alone.
		return
	}
	// ffmpeg keeps a replaced file open to the end, so an encode that started
	// before the replacement finishes cleanly — on the old file.
	if err == nil && m.sourceChanged(req.ItemID, identity, jobID, "work-after") {
		err = errStale
	}
	m.finish(jobID, identity, err)
}

// sourceChanged reports whether an item's file no longer matches identity. A
// failed lookup answers false: a stow is never failed over a query error, and a
// deleted item takes its job with it through the cascade anyway.
func (m *Manager) sourceChanged(itemID, identity, jobID, caught string) bool {
	current, ok := m.itemIdentity(itemID)
	if !ok || current == identity {
		return false
	}
	m.logger.Info("stow: source changed", "job", jobID, "item", itemID,
		"old", identity, "new", current, "caught", caught)
	return true
}

// itemIdentity reads an item's current fileid identity. ok is false when the
// item is gone or the query fails.
func (m *Manager) itemIdentity(itemID string) (string, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	var hash *string
	var size *int64
	err := m.pool.QueryRow(ctx,
		`SELECT content_hash, file_size FROM media_items WHERE id = $1`, itemID).Scan(&hash, &size)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			m.logger.Warn("stow: reading item identity failed", "item", itemID, "err", err)
		}
		return "", false
	}
	return fileid.Identity(hash, size), true
}

// finish records a job's terminal state, purging the artifact directory when the
// encode failed so a partial MP4 is never downloadable.
//
// Every write is guarded by the identity the worker was started with. A request
// that resets a job waits for its worker first, so this should never match a
// reset row anyway — but if it ever did, a superseded worker marking a reset job
// ready would hand over the old file's package, or its purge would delete the
// new worker's partial. The directory is only touched once the guarded write
// has claimed the row.
func (m *Manager) finish(jobID, identity string, err error) {
	if err != nil {
		msg := err.Error()
		if errors.Is(err, errStale) {
			m.logger.Info("stow: package superseded by a replaced file", "job", jobID)
			msg = StaleMessage
		} else {
			m.logger.Error("stow: packaging failed", "job", jobID, "err", err)
		}
		tag, sErr := m.pool.Exec(context.Background(),
			`UPDATE stow_jobs SET state = $2, error = $3, updated_at = now()
			 WHERE id = $1 AND source_identity = $4`,
			jobID, StateFailed, msg, identity)
		if sErr != nil {
			m.logger.Error("stow: mark failed", "job", jobID, "err", sErr)
			return
		}
		if tag.RowsAffected() == 0 {
			return // Deleted, or reset under a new source: not ours to purge.
		}
		if rmErr := os.RemoveAll(filepath.Join(m.workDir, jobID)); rmErr != nil {
			m.logger.Warn("stow: purge failed package", "job", jobID, "err", rmErr)
		}
		return
	}
	var size int64
	if fi, statErr := os.Stat(m.ArtifactPath(jobID)); statErr == nil {
		size = fi.Size()
	}
	tag, dbErr := m.pool.Exec(context.Background(), `
		UPDATE stow_jobs SET state = 'ready', output_bytes = $2, error = '',
		       ready_at = now(), updated_at = now()
		WHERE id = $1 AND source_identity = $3`, jobID, size, identity)
	if dbErr != nil {
		m.logger.Error("stow: mark ready", "job", jobID, "err", dbErr)
		return
	}
	if tag.RowsAffected() == 0 {
		m.logger.Warn("stow: finished package no longer matches its job, discarding", "job", jobID)
		return
	}
	m.logger.Info("stow: package ready", "job", jobID, "bytes", size)
}

// progressSink throttles ffmpeg's progress ticks (a few per second) down to a
// DB write every couple of seconds — the client polls far slower than ffmpeg
// reports, so writing every tick would be pure churn. Only the encoded position
// is stored; the client renders the percentage against duration_seconds, which
// was written when the job was queued.
func (m *Manager) progressSink(jobID, identity string) func(transcode.Progress) {
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
			`UPDATE stow_jobs SET progress_ms = $2, updated_at = now() WHERE id = $1 AND source_identity = $3`,
			jobID, p.OutTimeMS, identity); err != nil {
			m.logger.Warn("stow: progress update failed", "job", jobID, "err", err)
		}
	}
}

func (m *Manager) setState(jobID, identity string, st State, errMsg string) error {
	_, err := m.pool.Exec(context.Background(),
		`UPDATE stow_jobs SET state = $2, error = $3, updated_at = now() WHERE id = $1 AND source_identity = $4`,
		jobID, st, errMsg, identity)
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
//
// A job whose item's file has been replaced since it was made is reported as
// failed with StaleMessage (see Job.Stale). This is the path the phone polls
// while packaging and reads again before downloading, so it is where a ready
// package of a replaced file has to be caught.
func (m *Manager) Get(ctx context.Context, accountID, jobID string) (Job, bool, error) {
	var hash *string
	var size *int64
	j := Job{}
	err := m.pool.QueryRow(ctx,
		`SELECT `+jobColumns+`, mi.content_hash, mi.file_size
		 FROM stow_jobs sj JOIN media_items mi ON mi.id = sj.item_id
		 WHERE sj.id = $1 AND sj.account_id = $2`, jobID, accountID).Scan(
		&j.ID, &j.AccountID, &j.ItemID, &j.State, &j.Encoder, &j.OutputBytes,
		&j.DurationSeconds, &j.ProgressMS, &j.Err, &j.CreatedAt, &j.UpdatedAt, &j.ReadyAt,
		&j.SourceIdentity, &hash, &size)
	if errors.Is(err, pgx.ErrNoRows) {
		return Job{}, false, nil
	}
	if err != nil {
		return Job{}, false, err
	}
	if j.State != StateFailed && j.SourceIdentity != fileid.Identity(hash, size) {
		m.logger.Info("stow: source changed", "job", j.ID, "item", j.ItemID,
			"old", j.SourceIdentity, "new", fileid.Identity(hash, size), "caught", "get")
		j.State = StateFailed
		j.Err = StaleMessage
		j.Stale = true
	}
	return j, true, nil
}

// ByItem returns the account's job for an item, if it has one, as the row
// stands — no staleness mapping, since Request needs the recorded identity.
func (m *Manager) ByItem(ctx context.Context, accountID, itemID string) (Job, bool, error) {
	job, err := scanJob(m.pool.QueryRow(ctx,
		`SELECT `+jobColumns+` FROM stow_jobs sj WHERE sj.account_id = $1 AND sj.item_id = $2`, accountID, itemID))
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
		`SELECT `+jobColumns+` FROM stow_jobs sj WHERE sj.account_id = $1 ORDER BY sj.created_at DESC`, accountID)
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
	w := m.running[jobID]
	m.mu.Unlock()
	if w != nil {
		w.cancel()
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
