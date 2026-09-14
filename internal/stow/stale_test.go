package stow

// Stow jobs across a file replacement (ARGY-238): an item keeps its id when its
// file is replaced, so a job made from the old file has to say so rather than
// hand the old encode over as the item.

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/transcode"
)

func (f *fixture) setItemHash(t *testing.T, itemID, hash string) {
	t.Helper()
	if _, err := f.pool.Exec(context.Background(),
		`UPDATE media_items SET content_hash = $2 WHERE id = $1`, itemID, hash); err != nil {
		t.Fatal(err)
	}
}

func (f *fixture) requestFor(t *testing.T, itemID, identity string) Job {
	t.Helper()
	job, err := f.mgr.Request(context.Background(), Request{
		AccountID: f.account, ItemID: itemID, Source: "/media/film.mkv", SourceIdentity: identity,
		SourceHeight: 1080, DurationSeconds: 5400,
	})
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	return job
}

func (f *fixture) addItem(t *testing.T) string {
	t.Helper()
	var id string
	if err := f.pool.QueryRow(context.Background(), `
		INSERT INTO media_items (library_id, kind, title, file_path)
		SELECT library_id, 'movie', 'Second', file_path || '.second' FROM media_items WHERE id = $1
		RETURNING id::text`, f.item).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

// waitForRow polls the row itself, not Get: Get reports a stale job as failed
// straight away, and these tests are about what the worker wrote.
func waitForRow(t *testing.T, f *fixture, jobID string, want State) string {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	var state, errMsg string
	for time.Now().Before(deadline) {
		if err := f.pool.QueryRow(context.Background(),
			`SELECT state, error FROM stow_jobs WHERE id = $1`, jobID).Scan(&state, &errMsg); err != nil {
			t.Fatalf("read job row: %v", err)
		}
		if State(state) == want {
			return errMsg
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("job row stuck in %q (error %q), want %q", state, errMsg, want)
	return ""
}

// TestGetReportsStalePackage: a ready package whose item's file was replaced is
// reported failed with the re-stow message — on the path the phone polls.
func TestGetReportsStalePackage(t *testing.T) {
	f := newFixture(t)
	f.setItemHash(t, f.item, "hash-1")
	job := f.requestFor(t, f.item, "hash-1")
	close(f.backend.release)
	waitForState(t, f.mgr, f.account, job.ID, StateReady)

	f.setItemHash(t, f.item, "hash-2")
	got, ok, err := f.mgr.Get(context.Background(), f.account, job.ID)
	if err != nil || !ok {
		t.Fatalf("get: ok %v, err %v", ok, err)
	}
	if !got.Stale || got.State != StateFailed || got.Err != StaleMessage {
		t.Fatalf("stale job reported as %+v, want failed/stale with %q", got, StaleMessage)
	}
	// Reporting rewrites nothing: the row and its artifact are Delete's, or a
	// new request's, to deal with.
	if msg := waitForRow(t, f, job.ID, StateReady); msg != "" {
		t.Errorf("row error = %q, want untouched", msg)
	}
	if _, err := os.Stat(f.mgr.ArtifactPath(job.ID)); err != nil {
		t.Errorf("Get purged the artifact: %v", err)
	}
}

// TestUnchangedSourceIsNotStale: the everyday case must not trip the check.
func TestUnchangedSourceIsNotStale(t *testing.T) {
	f := newFixture(t)
	f.setItemHash(t, f.item, "hash-1")
	job := f.requestFor(t, f.item, "hash-1")
	close(f.backend.release)
	if got := waitForState(t, f.mgr, f.account, job.ID, StateReady); got.Stale {
		t.Fatalf("a job over an unchanged file reported stale: %+v", got)
	}
}

// TestPendingJobFailsBeforeEncoding: a job queued behind the concurrency limit
// whose file is replaced while it waits fails with the re-stow message instead
// of running ffmpeg against a path that is gone.
func TestPendingJobFailsBeforeEncoding(t *testing.T) {
	f := newFixture(t)
	second := f.addItem(t)
	f.setItemHash(t, second, "hash-1")

	first := f.request(t)
	waitForState(t, f.mgr, f.account, first.ID, StatePackaging)
	queued := f.requestFor(t, second, "hash-1")
	if queued.State != StatePending {
		t.Fatalf("second job = %q, want it queued", queued.State)
	}

	f.setItemHash(t, second, "hash-2")
	close(f.backend.release)
	waitForState(t, f.mgr, f.account, first.ID, StateReady)
	if msg := waitForRow(t, f, queued.ID, StateFailed); msg != StaleMessage {
		t.Errorf("queued job error = %q, want %q", msg, StaleMessage)
	}
	if n := f.backend.callCount(); n != 1 {
		t.Errorf("packager ran %d times, want 1 — the stale job must not encode", n)
	}
}

// TestEncodeFinishingAfterReplacementFails: ffmpeg keeps a replaced file open,
// so an encode already running finishes cleanly — on the old file. It must end
// failed, with its artifact purged, not ready.
func TestEncodeFinishingAfterReplacementFails(t *testing.T) {
	f := newFixture(t)
	f.setItemHash(t, f.item, "hash-1")
	job := f.requestFor(t, f.item, "hash-1")
	waitForState(t, f.mgr, f.account, job.ID, StatePackaging)

	f.setItemHash(t, f.item, "hash-2")
	close(f.backend.release)
	if msg := waitForRow(t, f, job.ID, StateFailed); msg != StaleMessage {
		t.Errorf("job error = %q, want %q", msg, StaleMessage)
	}
	if _, err := os.Stat(filepath.Join(f.workDir, job.ID)); !os.IsNotExist(err) {
		t.Errorf("the old file's package was left behind (stat err %v)", err)
	}
}

// TestRequestRepackagesStaleJob: requesting an item whose job was made from a
// replaced file stops the old encode, then re-packages the new file on the same
// job id — so a phone already polling that id sees it restart.
func TestRequestRepackagesStaleJob(t *testing.T) {
	f := newFixture(t)
	f.setItemHash(t, f.item, "hash-1")
	job := f.requestFor(t, f.item, "hash-1")
	waitForState(t, f.mgr, f.account, job.ID, StatePackaging)

	f.setItemHash(t, f.item, "hash-2")
	again := f.requestFor(t, f.item, "hash-2")
	if again.ID != job.ID {
		t.Fatalf("re-request made job %s, want the same id %s", again.ID, job.ID)
	}
	if again.State != StatePending || again.SourceIdentity != "hash-2" {
		t.Fatalf("re-request = %+v, want pending over hash-2", again)
	}

	deadline := time.Now().Add(10 * time.Second)
	for f.backend.callCount() < 2 {
		if time.Now().After(deadline) {
			t.Fatalf("packager ran %d times, want a second encode for the new file", f.backend.callCount())
		}
		time.Sleep(20 * time.Millisecond)
	}
	close(f.backend.release)
	ready := waitForState(t, f.mgr, f.account, job.ID, StateReady)
	if ready.SourceIdentity != "hash-2" || ready.Stale {
		t.Errorf("finished job = %+v, want ready over hash-2", ready)
	}
}

// TestSupersededWorkerCannotFinishResetJob pins the guard under the wait: even
// if a worker outlived the reset of its job, its finish must neither mark the
// reset row ready nor purge the directory the new worker is writing into.
func TestSupersededWorkerCannotFinishResetJob(t *testing.T) {
	f := newFixture(t)
	f.setItemHash(t, f.item, "hash-1")
	job := f.requestFor(t, f.item, "hash-1")
	waitForState(t, f.mgr, f.account, job.ID, StatePackaging)
	t.Cleanup(func() { _, _ = f.mgr.Delete(context.Background(), f.account, job.ID) })

	if _, err := f.pool.Exec(context.Background(),
		`UPDATE stow_jobs SET state = 'pending', source_identity = 'hash-2' WHERE id = $1`, job.ID); err != nil {
		t.Fatal(err)
	}
	partial := filepath.Join(f.workDir, job.ID, transcode.PackageName)
	if err := os.WriteFile(partial, []byte("new worker's partial"), 0o644); err != nil {
		t.Fatal(err)
	}

	f.mgr.finish(job.ID, "hash-1", nil)
	waitForRow(t, f, job.ID, StatePending)
	f.mgr.finish(job.ID, "hash-1", errors.New("old encode failed"))
	waitForRow(t, f, job.ID, StatePending)
	if _, err := os.Stat(partial); err != nil {
		t.Errorf("a superseded worker's failure purged the new worker's output: %v", err)
	}
}
