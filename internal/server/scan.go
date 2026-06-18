package server

import (
	"net/http"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/stevedore"
	"github.com/google/uuid"
)

// scanHandlers expose Stevedore's scheduler: a manual "rebuild the Manifest"
// trigger and an observable status endpoint.
type scanHandlers struct{ sched *stevedore.Scheduler }

func (h *scanHandlers) status(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, toAPIScanStatus(h.sched.Snapshot()))
}

func (h *scanHandlers) trigger(w http.ResponseWriter, _ *http.Request) {
	if h.sched.Trigger() {
		w.WriteHeader(http.StatusAccepted)
		return
	}
	w.WriteHeader(http.StatusConflict)
}

func toAPIScanStatus(s stevedore.Status) api.ScanStatus {
	out := api.ScanStatus{
		Running:    s.Running,
		StartedAt:  s.StartedAt,
		FinishedAt: s.FinishedAt,
		Libraries:  []api.ScanLibraryResult{},
	}
	for _, l := range s.Libraries {
		r := api.ScanLibraryResult{
			LibraryId: parseUUID(l.LibraryID),
			Name:      l.Name,
			Scanned:   l.Scanned,
			Errors:    l.Errors,
		}
		if l.Error != "" {
			e := l.Error
			r.Error = &e
		}
		out.Libraries = append(out.Libraries, r)
	}
	return out
}

func parseUUID(s string) uuid.UUID {
	u, _ := uuid.Parse(s)
	return u
}
