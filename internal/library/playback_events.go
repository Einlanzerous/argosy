package library

import (
	"math"
	"net/http"
	"strconv"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/httpx"
)

// maxStallMs bounds a reported stall. A client that was backgrounded mid-stall
// can report days; past a day it is a bug, not a stall, and is refused rather
// than logged as if it were real.
const maxStallMs = 24 * 60 * 60 * 1000

// reportPlaybackEvent logs one client-side playback event (ARGY-313).
//
// The server cannot see a rebuffer from the progress heartbeat, which fires on
// a timer whatever the player is doing, so the player reports each stall and
// this writes it to the log. Nothing is stored, and the resume position, the
// presence registry and the Beacon are untouched: an event is an observation,
// not a state change.
//
// The line carries ids and numbers only — never a title or a file path. The
// account is shortened the way the request log shortens it, and the device is
// named the same way, so a stall greps against the request lines around it.
func (h *handlers) reportPlaybackEvent(w http.ResponseWriter, r *http.Request) {
	var body api.PlaybackEvent
	if !decodeJSON(w, r, &body) {
		return
	}
	if body.Kind != api.Stall {
		httpx.Error(w, http.StatusBadRequest, "unknown event kind")
		return
	}
	switch body.Cause {
	case api.Seek, api.Resume, api.Play:
	default:
		httpx.Error(w, http.StatusBadRequest, "unknown stall cause")
		return
	}
	pos := float64(body.PositionSeconds)
	if math.IsNaN(pos) || math.IsInf(pos, 0) || pos < 0 {
		httpx.Error(w, http.StatusBadRequest, "positionSeconds is out of range")
		return
	}
	if body.DurationMs < 0 || body.DurationMs > maxStallMs {
		httpx.Error(w, http.StatusBadRequest, "durationMs is out of range")
		return
	}
	ahead := -1.0
	if body.BufferedAheadSeconds != nil {
		ahead = float64(*body.BufferedAheadSeconds)
		if math.IsNaN(ahead) || math.IsInf(ahead, 0) || ahead < 0 {
			httpx.Error(w, http.StatusBadRequest, "bufferedAheadSeconds is out of range")
			return
		}
	}
	if body.Delivery != nil {
		switch *body.Delivery {
		case api.PlaybackEventDeliveryDirect, api.PlaybackEventDeliveryRemux, api.PlaybackEventDeliveryTranscode:
		default:
			httpx.Error(w, http.StatusBadRequest, "unknown delivery")
			return
		}
	}
	// The session id is client-supplied text that lands in a log line, so it
	// has to look like an id: short and free of anything that could forge a
	// field or a second line.
	sessionID := "-"
	if body.SessionId != nil && *body.SessionId != "" {
		if !plausibleID(*body.SessionId) {
			httpx.Error(w, http.StatusBadRequest, "sessionId is malformed")
			return
		}
		sessionID = *body.SessionId
	}

	itemID := r.PathValue("itemId")
	ok, err := h.store.itemInAccount(r.Context(), catalogOf(r), itemID)
	if err != nil {
		h.fail(w, err)
		return
	}
	if !ok {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}

	accountID, _, _ := auth.TraceFromContext(r.Context()).Identity()
	account := "-"
	if accountID != "" {
		account = accountID[:min(8, len(accountID))]
	}
	aheadField := "-"
	if ahead >= 0 {
		aheadField = strconv.FormatFloat(ahead, 'f', 1, 64)
	}
	delivery := "-"
	if body.Delivery != nil {
		delivery = string(*body.Delivery)
	}
	recovered := body.Recovered != nil && *body.Recovered
	// A recovered stall was cut short by definition; "ended=true recovered=true"
	// would read as a contradiction in the log.
	ended := (body.Ended == nil || *body.Ended) && !recovered

	h.logger.Info("playback stall",
		"req", w.Header().Get("X-Request-Id"),
		"device", auth.DeviceLabel(r.Context()),
		"account", account,
		"item", itemID,
		"session", sessionID,
		"cause", string(body.Cause),
		"dur_ms", body.DurationMs,
		"ended", ended,
		"recovered", recovered,
		"pos", strconv.FormatFloat(pos, 'f', 1, 64),
		"ahead_s", aheadField,
		"delivery", delivery,
	)
	w.WriteHeader(http.StatusNoContent)
}

// plausibleID reports whether s could be a transcode session id: short, and
// only characters an id is made of.
func plausibleID(s string) bool {
	if len(s) == 0 || len(s) > 64 {
		return false
	}
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9', c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c == '-', c == '_':
		default:
			return false
		}
	}
	return true
}
