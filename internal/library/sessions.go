package library

import (
	"net/http"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/presence"
	"github.com/Einlanzerous/argosy/internal/transcode"
)

// listSessions returns the live playback sessions the caller may see: an admin
// sees the whole account's Fleet, a viewer only their own. Each session that
// owns a live transcode session is annotated with its encoder + method
// (reconciled with The Helm).
func (h *handlers) listSessions(w http.ResponseWriter, r *http.Request) {
	sess, _ := auth.SessionFromContext(r.Context())
	var live []presence.Session
	if sess.Role == api.Admin {
		live = h.presence.Active(sess.AccountId.String())
	} else {
		live = h.presence.ActiveForUser(sess.UserId.String())
	}

	// Index live transcode sessions by (account, item) to reconcile ownership.
	type tkey struct{ acc, item string }
	tx := map[tkey]transcode.Session{}
	if h.tc != nil {
		for _, ts := range h.tc.List() {
			tx[tkey{ts.AccountID, ts.ItemID}] = ts
		}
	}

	out := make([]api.PlaybackSession, 0, len(live))
	for _, s := range live {
		ps := api.PlaybackSession{
			UserId:          parseUUID(s.UserID),
			DeviceId:        parseUUID(s.DeviceID),
			ItemId:          parseUUID(s.ItemID),
			PositionSeconds: s.PositionSeconds,
			State:           s.State,
			StartedAt:       s.StartedAt,
			LastSeen:        s.LastSeen,
		}
		if s.DurationSeconds > 0 {
			d := s.DurationSeconds
			ps.DurationSeconds = &d
		}
		if ts, ok := tx[tkey{s.AccountID, s.ItemID}]; ok {
			enc, m := ts.Encoder, ts.Method
			ps.Encoder = &enc
			ps.Method = &m
		}
		out = append(out, ps)
	}
	httpx.JSON(w, http.StatusOK, out)
}
