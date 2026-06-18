package server

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/stevedore"
)

func TestScanHandlers(t *testing.T) {
	// nil pool is fine: we exercise the handler/scheduler plumbing, not a sweep.
	sched := stevedore.NewScheduler(nil, slog.New(slog.NewTextHandler(io.Discard, nil)), "", nil, 0)
	h := &scanHandlers{sched: sched}

	rec := httptest.NewRecorder()
	h.status(rec, httptest.NewRequest(http.MethodGet, "/api/v1/scan/status", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status code = %d, want 200", rec.Code)
	}
	var st api.ScanStatus
	if err := json.NewDecoder(rec.Body).Decode(&st); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if st.Running || st.Libraries == nil {
		t.Errorf("fresh status = %+v, want not running with non-nil libraries", st)
	}

	// First trigger is accepted; a second (with no consumer draining the queue)
	// is rejected as already-queued.
	rec1 := httptest.NewRecorder()
	h.trigger(rec1, httptest.NewRequest(http.MethodPost, "/api/v1/scan", nil))
	if rec1.Code != http.StatusAccepted {
		t.Fatalf("first trigger = %d, want 202", rec1.Code)
	}
	rec2 := httptest.NewRecorder()
	h.trigger(rec2, httptest.NewRequest(http.MethodPost, "/api/v1/scan", nil))
	if rec2.Code != http.StatusConflict {
		t.Fatalf("second trigger = %d, want 409", rec2.Code)
	}
}

func TestToAPIScanStatus(t *testing.T) {
	s := stevedore.Status{
		Running: false,
		Libraries: []stevedore.LibraryScan{
			{LibraryID: "11111111-1111-1111-1111-111111111111", Name: "Films", Scanned: 3, Errors: 1, Error: "boom"},
		},
	}
	out := toAPIScanStatus(s)
	if len(out.Libraries) != 1 {
		t.Fatalf("libraries = %d, want 1", len(out.Libraries))
	}
	l := out.Libraries[0]
	if l.Name != "Films" || l.Scanned != 3 || l.Errors != 1 {
		t.Errorf("mapped library = %+v", l)
	}
	if l.Error == nil || *l.Error != "boom" {
		t.Errorf("error = %v, want boom", l.Error)
	}
	if l.LibraryId.String() != "11111111-1111-1111-1111-111111111111" {
		t.Errorf("libraryId = %s", l.LibraryId)
	}
}
