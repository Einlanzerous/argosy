// Package presence tracks live playback sessions — who is watching what, on
// which device, right now. It is the read model behind "active sessions" in The
// Helm and underpins cross-device resume/handoff (Phase 4).
//
// Sessions live in memory (one process; the single-binary household server, same
// model as The Helm's transcode sessions) and are driven by the existing
// progress heartbeat: each beat refreshes a session, and sessions idle beyond a
// TTL are reaped (client stopped, navigated away, or crashed). A session is
// identified deterministically by (user, device, item) so repeated beats and
// brief client reconnects refresh one session instead of spawning duplicates.
package presence

import (
	"context"
	"sort"
	"sync"
	"time"
)

// StatePlaying marks a session that is actively playing.
const StatePlaying = "playing"

// Session is a live playback session.
type Session struct {
	AccountID       string    `json:"-"`
	UserID          string    `json:"userId"`
	DeviceID        string    `json:"deviceId"`
	ItemID          string    `json:"itemId"`
	PositionSeconds float64   `json:"positionSeconds"`
	DurationSeconds float64   `json:"durationSeconds,omitempty"`
	State           string    `json:"state"`
	StartedAt       time.Time `json:"startedAt"`
	LastSeen        time.Time `json:"lastSeen"`
}

// Registry holds the live set of playback sessions.
type Registry struct {
	ttl   time.Duration
	clock func() time.Time

	mu       sync.Mutex
	sessions map[string]*Session
}

// NewRegistry returns a presence registry. ttl is how long a session may go
// without a heartbeat before it's reaped (default 45s — ~4 missed 10s beats).
func NewRegistry(ttl time.Duration) *Registry {
	if ttl <= 0 {
		ttl = 45 * time.Second
	}
	return &Registry{ttl: ttl, clock: time.Now, sessions: make(map[string]*Session)}
}

func key(userID, deviceID, itemID string) string {
	return userID + "|" + deviceID + "|" + itemID
}

// Heartbeat records or refreshes a live session from a progress beat. A new
// session is stamped StartedAt; an existing one keeps its StartedAt and just
// advances position + LastSeen. Returns the resulting snapshot.
func (r *Registry) Heartbeat(s Session) Session {
	now := r.clock()
	if s.State == "" {
		s.State = StatePlaying
	}
	k := key(s.UserID, s.DeviceID, s.ItemID)
	r.mu.Lock()
	defer r.mu.Unlock()
	if cur, ok := r.sessions[k]; ok {
		cur.AccountID = s.AccountID
		cur.PositionSeconds = s.PositionSeconds
		if s.DurationSeconds > 0 {
			cur.DurationSeconds = s.DurationSeconds
		}
		cur.State = s.State
		cur.LastSeen = now
		return *cur
	}
	s.StartedAt = now
	s.LastSeen = now
	cp := s
	r.sessions[k] = &cp
	return cp
}

// Close removes a session (explicit stop). No-op if unknown.
func (r *Registry) Close(userID, deviceID, itemID string) {
	r.mu.Lock()
	delete(r.sessions, key(userID, deviceID, itemID))
	r.mu.Unlock()
}

// Active returns the account's live sessions, most-recently-active first.
func (r *Registry) Active(accountID string) []Session {
	return r.filter(func(s *Session) bool { return s.AccountID == accountID })
}

// CountPlaying returns how many sessions are in the playing state across ALL
// accounts, plus the instant it was read. It is the one number behind the
// service-token summary route (ARGY-325) and deliberately returns no session,
// user, device or item: the caller it exists for may learn a count and nothing
// else. Active(accountID) is the per-account view and stays that.
//
// A session past the TTL is not counted even if the reaper has not swept it
// yet (the sweep runs every ttl/2), so the count never lags the TTL.
func (r *Registry) CountPlaying() (int, time.Time) {
	now := r.clock()
	cutoff := now.Add(-r.ttl)
	r.mu.Lock()
	defer r.mu.Unlock()
	n := 0
	for _, s := range r.sessions {
		if s.State == StatePlaying && !s.LastSeen.Before(cutoff) {
			n++
		}
	}
	return n, now
}

// ActiveForUser returns a single user's live sessions, most-recently-active first.
func (r *Registry) ActiveForUser(userID string) []Session {
	return r.filter(func(s *Session) bool { return s.UserID == userID })
}

func (r *Registry) filter(pred func(*Session) bool) []Session {
	r.mu.Lock()
	out := make([]Session, 0, len(r.sessions))
	for _, s := range r.sessions {
		if pred(s) {
			out = append(out, *s)
		}
	}
	r.mu.Unlock()
	sort.Slice(out, func(i, j int) bool { return out[i].LastSeen.After(out[j].LastSeen) })
	return out
}

// reap drops sessions idle beyond the TTL.
func (r *Registry) reap() {
	cutoff := r.clock().Add(-r.ttl)
	r.mu.Lock()
	for k, s := range r.sessions {
		if s.LastSeen.Before(cutoff) {
			delete(r.sessions, k)
		}
	}
	r.mu.Unlock()
}

// Run drives the idle reaper until ctx is cancelled. Call it in a goroutine.
func (r *Registry) Run(ctx context.Context) {
	interval := r.ttl / 2
	if interval < time.Second {
		interval = time.Second
	}
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			r.reap()
		}
	}
}
