package stow

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/jackc/pgx/v5/pgxpool"
)

func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

// fakePackager stands in for ffmpeg: it blocks until released, then writes a
// stub artifact (or fails). It lets the test drive every state transition
// without encoding anything.
type fakePackager struct {
	mu       sync.Mutex
	release  chan struct{}
	started  chan struct{}
	err      error
	contents string
	calls    int
	lastSpec transcode.PackageSpec
}

func newFakePackager() *fakePackager {
	return &fakePackager{
		release:  make(chan struct{}),
		started:  make(chan struct{}, 8),
		contents: "packaged-bytes",
	}
}

func (f *fakePackager) Package(ctx context.Context, spec transcode.PackageSpec, onProgress func(transcode.Progress)) error {
	f.mu.Lock()
	f.calls++
	f.lastSpec = spec
	failWith := f.err
	body := f.contents
	f.mu.Unlock()

	select {
	case f.started <- struct{}{}:
	default:
	}
	if onProgress != nil {
		onProgress(transcode.Progress{OutTimeMS: 1234})
	}
	select {
	case <-f.release:
	case <-ctx.Done():
		return ctx.Err()
	}
	if failWith != nil {
		return failWith
	}
	return os.WriteFile(filepath.Join(spec.OutputDir, transcode.PackageName), []byte(body), 0o644)
}

func (f *fakePackager) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

// waitForState polls a job until it reaches want, so the test never races the
// worker goroutine.
func waitForState(t *testing.T, m *Manager, accountID, jobID string, want State) Job {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	var last Job
	for time.Now().Before(deadline) {
		job, ok, err := m.Get(context.Background(), accountID, jobID)
		if err != nil {
			t.Fatalf("get job: %v", err)
		}
		if !ok {
			t.Fatalf("job %s vanished while waiting for %q", jobID, want)
		}
		last = job
		if job.State == want {
			return job
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("job stuck in %q (error %q), want %q", last.State, last.Err, want)
	return Job{}
}

type fixture struct {
	pool    *pgxpool.Pool
	mgr     *Manager
	backend *fakePackager
	workDir string
	account string
	item    string
}

func newFixture(t *testing.T) *fixture {
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

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID, itemID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "stow_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Film',$2) RETURNING id::text`,
		libID, "film-"+suffix+".mkv").Scan(&itemID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, accID)
	})

	backend := newFakePackager()
	workDir := t.TempDir()
	return &fixture{
		pool:    pool,
		mgr:     New(pool, backend, workDir, transcode.EncoderSoftware, 1, 0, discardLogger()),
		backend: backend,
		workDir: workDir,
		account: accID,
		item:    itemID,
	}
}

func (f *fixture) request(t *testing.T) Job {
	t.Helper()
	job, err := f.mgr.Request(context.Background(), Request{
		AccountID: f.account, ItemID: f.item, Source: "/media/film.mkv",
		SourceHeight: 1080, DurationSeconds: 5400,
	})
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	return job
}

// TestPackagingLifecycle walks a job from request to ready and checks the
// artifact is where the download handler will look for it.
func TestPackagingLifecycle(t *testing.T) {
	f := newFixture(t)

	job := f.request(t)
	if job.State != StatePending {
		t.Fatalf("initial state = %q, want %q", job.State, StatePending)
	}
	waitForState(t, f.mgr, f.account, job.ID, StatePackaging)

	close(f.backend.release)
	ready := waitForState(t, f.mgr, f.account, job.ID, StateReady)

	if ready.OutputBytes != int64(len("packaged-bytes")) {
		t.Errorf("outputBytes = %d, want the artifact's size", ready.OutputBytes)
	}
	if ready.ReadyAt == nil {
		t.Error("readyAt is nil on a ready job")
	}
	if _, err := os.Stat(f.mgr.ArtifactPath(job.ID)); err != nil {
		t.Errorf("artifact missing at ArtifactPath: %v", err)
	}
	// Progress reached the DB from the encode.
	if ready.DurationSeconds != 5400 {
		t.Errorf("durationSeconds = %v, want 5400 (the client renders progress against it)", ready.DurationSeconds)
	}
}

// TestRepeatRequestJoinsExistingJob is the guard against a second ffmpeg being
// spawned over the same source — the reason (account, item) is unique.
func TestRepeatRequestJoinsExistingJob(t *testing.T) {
	f := newFixture(t)

	first := f.request(t)
	waitForState(t, f.mgr, f.account, first.ID, StatePackaging)

	second := f.request(t)
	if second.ID != first.ID {
		t.Fatalf("second request made job %s, want it to join %s", second.ID, first.ID)
	}

	close(f.backend.release)
	waitForState(t, f.mgr, f.account, first.ID, StateReady)

	if n := f.backend.callCount(); n != 1 {
		t.Errorf("packager ran %d times, want 1 — a repeat stow must join, not duplicate the encode", n)
	}
}

// TestFailedJobRetries covers the one state a new request is allowed to rewrite.
func TestFailedJobRetries(t *testing.T) {
	f := newFixture(t)
	f.backend.err = errors.New("ffmpeg exploded")

	job := f.request(t)
	close(f.backend.release)
	failed := waitForState(t, f.mgr, f.account, job.ID, StateFailed)
	if failed.Err == "" {
		t.Error("failed job carries no error; the client has nothing to show")
	}
	// A failed encode must not leave a partial artifact that the download
	// endpoint would happily serve.
	if _, err := os.Stat(filepath.Join(f.workDir, job.ID)); !os.IsNotExist(err) {
		t.Errorf("failed job left its directory behind (stat err %v)", err)
	}

	// Re-requesting resets the same row rather than inserting beside it.
	f.backend.mu.Lock()
	f.backend.err = nil
	f.backend.release = make(chan struct{})
	f.backend.mu.Unlock()

	retry := f.request(t)
	if retry.ID != job.ID {
		t.Fatalf("retry made job %s, want the same row %s reset", retry.ID, job.ID)
	}
	if retry.State != StatePending {
		t.Fatalf("retry state = %q, want %q", retry.State, StatePending)
	}
	if retry.Err != "" {
		t.Errorf("retry still carries the old error %q", retry.Err)
	}

	f.backend.mu.Lock()
	release := f.backend.release
	f.backend.mu.Unlock()
	close(release)
	waitForState(t, f.mgr, f.account, job.ID, StateReady)
}

// TestDeleteCancelsAndPurges covers the cancel half of the AC: an encode in
// flight stops, and neither the row nor the artifact survives.
func TestDeleteCancelsAndPurges(t *testing.T) {
	f := newFixture(t)

	job := f.request(t)
	waitForState(t, f.mgr, f.account, job.ID, StatePackaging)

	ok, err := f.mgr.Delete(context.Background(), f.account, job.ID)
	if err != nil || !ok {
		t.Fatalf("delete = %v, %v; want true, nil", ok, err)
	}
	if _, found, err := f.mgr.Get(context.Background(), f.account, job.ID); err != nil || found {
		t.Errorf("job still present after delete (found %v, err %v)", found, err)
	}
	// Give the cancelled worker a moment to unwind, then confirm it didn't
	// resurrect the directory on its way out.
	time.Sleep(200 * time.Millisecond)
	if _, err := os.Stat(filepath.Join(f.workDir, job.ID)); !os.IsNotExist(err) {
		t.Errorf("artifact directory survived delete (stat err %v)", err)
	}
}

// TestJobsAreAccountScoped is the access check: one household member must not be
// able to see or cancel another's job by guessing its id.
func TestJobsAreAccountScoped(t *testing.T) {
	f := newFixture(t)
	job := f.request(t)
	close(f.backend.release)
	waitForState(t, f.mgr, f.account, job.ID, StateReady)

	ctx := context.Background()
	var otherID string
	if err := f.pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`,
		"stow_other_"+strconv.FormatInt(time.Now().UnixNano(), 36)).Scan(&otherID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = f.pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, otherID) })

	if _, found, err := f.mgr.Get(ctx, otherID, job.ID); err != nil || found {
		t.Errorf("another account can read the job (found %v, err %v)", found, err)
	}
	if ok, err := f.mgr.Delete(ctx, otherID, job.ID); err != nil || ok {
		t.Errorf("another account can delete the job (ok %v, err %v)", ok, err)
	}
	jobs, err := f.mgr.List(ctx, otherID)
	if err != nil || len(jobs) != 0 {
		t.Errorf("List for another account = %d jobs (err %v), want 0", len(jobs), err)
	}
	// And the owner still sees it.
	jobs, err = f.mgr.List(ctx, f.account)
	if err != nil || len(jobs) != 1 {
		t.Fatalf("List for the owner = %d jobs (err %v), want 1", len(jobs), err)
	}
}

// TestLiveIDsCoversUncollectedPackages pins what Ballast is told to keep. A
// ready package nobody has downloaded yet must survive the sweeper; a failed
// job holds no artifact, so its directory is fair game.
func TestLiveIDsCoversUncollectedPackages(t *testing.T) {
	f := newFixture(t)
	job := f.request(t)
	waitForState(t, f.mgr, f.account, job.ID, StatePackaging)

	if live := f.mgr.LiveIDs(); !live[job.ID] {
		t.Error("a packaging job is not live; Ballast would reclaim the directory mid-encode")
	}
	close(f.backend.release)
	waitForState(t, f.mgr, f.account, job.ID, StateReady)
	if live := f.mgr.LiveIDs(); !live[job.ID] {
		t.Error("a ready, uncollected package is not live; Ballast would delete it before the device fetched it")
	}

	if err := f.mgr.setState(job.ID, StateFailed, "boom"); err != nil {
		t.Fatal(err)
	}
	if live := f.mgr.LiveIDs(); live[job.ID] {
		t.Error("a failed job is still live; its directory would never be reclaimed")
	}
}

// TestResetInterrupted covers the restart path: a job left mid-encode by a dead
// process must not sit pending forever with no worker attached to it.
func TestResetInterrupted(t *testing.T) {
	f := newFixture(t)
	job := f.request(t)
	waitForState(t, f.mgr, f.account, job.ID, StatePackaging)

	if err := f.mgr.ResetInterrupted(context.Background()); err != nil {
		t.Fatalf("reset: %v", err)
	}
	got, ok, err := f.mgr.Get(context.Background(), f.account, job.ID)
	if err != nil || !ok {
		t.Fatalf("get after reset: %v, %v", ok, err)
	}
	if got.State != StateFailed {
		t.Errorf("state = %q after reset, want %q", got.State, StateFailed)
	}
	if got.Err == "" {
		t.Error("reset job carries no explanation; the user is told nothing about why it stopped")
	}
	// Unlike the production caller (boot, before any worker exists) this test has
	// a live encode parked on release, and it writes its artifact under the
	// fixture's t.TempDir(). Returning straight after the close raced that write
	// against TempDir's RemoveAll — an intermittent "directory not empty" cleanup
	// failure with no connection to what the test asserts. Waiting for the worker
	// to run itself out leaves the directory quiescent; it lands on ready because
	// finish() is indifferent to the row having been reset underneath it.
	close(f.backend.release)
	waitForState(t, f.mgr, f.account, job.ID, StateReady)
}

// TestConcurrencyLimitQueues checks a second item waits its turn rather than
// running a competing encode — packaging shares the encoder with live playback.
func TestConcurrencyLimitQueues(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var libID, secondItem string
	if err := f.pool.QueryRow(ctx, `SELECT id::text FROM libraries WHERE account_id = $1`, f.account).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := f.pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Second',$2) RETURNING id::text`,
		libID, "second-"+suffix+".mkv").Scan(&secondItem); err != nil {
		t.Fatal(err)
	}

	first := f.request(t)
	waitForState(t, f.mgr, f.account, first.ID, StatePackaging)

	second, err := f.mgr.Request(ctx, Request{
		AccountID: f.account, ItemID: secondItem, Source: "/media/second.mkv", SourceHeight: 1080,
	})
	if err != nil {
		t.Fatalf("second request: %v", err)
	}
	// The limit is 1, so the second job stays visibly queued.
	time.Sleep(300 * time.Millisecond)
	got, _, err := f.mgr.Get(ctx, f.account, second.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.State != StatePending {
		t.Errorf("second job state = %q, want %q while the first holds the only slot", got.State, StatePending)
	}
	if n := f.backend.callCount(); n != 1 {
		t.Errorf("packager ran %d times, want 1 — the limit is not being enforced", n)
	}

	// Releasing the first lets the second through.
	close(f.backend.release)
	waitForState(t, f.mgr, f.account, first.ID, StateReady)
	waitForState(t, f.mgr, f.account, second.ID, StateReady)
}

// TestSweepDropsUncollectedPackages covers the retention clock — the backstop
// for a device that never came back for its download.
func TestSweepDropsUncollectedPackages(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()

	job := f.request(t)
	close(f.backend.release)
	waitForState(t, f.mgr, f.account, job.ID, StateReady)

	// Still fresh: the sweep leaves it alone.
	f.mgr.sweep(ctx)
	if _, ok, _ := f.mgr.Get(ctx, f.account, job.ID); !ok {
		t.Fatal("sweep removed a package that was still within retention")
	}

	// Age it past the retention window.
	if _, err := f.pool.Exec(ctx,
		`UPDATE stow_jobs SET ready_at = now() - interval '30 days' WHERE id = $1`, job.ID); err != nil {
		t.Fatal(err)
	}
	f.mgr.sweep(ctx)
	if _, ok, _ := f.mgr.Get(ctx, f.account, job.ID); ok {
		t.Error("sweep kept a package well past its retention window")
	}
}
