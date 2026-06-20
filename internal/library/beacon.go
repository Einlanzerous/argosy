package library

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/beacon"
)

// beaconHandler streams Server-Sent Events of the authenticated user's
// play-state changes (Beacon, ARGY-36) to their other devices. Auth is via
// ?token= because an EventSource can't set the Authorization header. The handler
// keeps the connection open, writing `event: position` frames as they arrive and
// a periodic comment ping to keep intermediaries from closing an idle stream.
func beaconHandler(authStore *auth.Store, hub *beacon.Hub) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := streamToken(r)
		if token == "" {
			writeJSON(w, http.StatusUnauthorized, errorBody("missing token"))
			return
		}
		sess, err := authStore.AuthenticateDevice(r.Context(), token)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, errorBody("invalid or revoked token"))
			return
		}
		flusher, ok := w.(http.Flusher)
		if !ok {
			writeJSON(w, http.StatusInternalServerError, errorBody("streaming unsupported"))
			return
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.Header().Set("X-Accel-Buffering", "no") // don't let a proxy buffer the stream
		w.WriteHeader(http.StatusOK)

		events, unsubscribe := hub.Subscribe(sess.UserId.String())
		defer unsubscribe()

		// Open the stream promptly so the client's onopen fires.
		_, _ = w.Write([]byte(": connected\n\n"))
		flusher.Flush()

		ping := time.NewTicker(25 * time.Second)
		defer ping.Stop()
		ctx := r.Context()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ping.C:
				if _, err := w.Write([]byte(": ping\n\n")); err != nil {
					return
				}
				flusher.Flush()
			case ev := <-events:
				payload, err := json.Marshal(ev)
				if err != nil {
					continue
				}
				if _, err := w.Write([]byte("event: position\ndata: " + string(payload) + "\n\n")); err != nil {
					return
				}
				flusher.Flush()
			}
		}
	}
}
