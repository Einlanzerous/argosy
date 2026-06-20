// Package beacon broadcasts live play-state changes to a user's other devices
// so cross-device resume/handoff feels instant (Phase 4). It uses Postgres
// LISTEN/NOTIFY as the event bus — no separate broker — fanned out to clients
// over SSE. One LISTEN connection serves the whole process; publishing is a
// NOTIFY, so any writer triggers delivery, not just this instance.
package beacon

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// channel is the Postgres NOTIFY channel. It's a constant (never interpolated
// from input), so concatenating it into LISTEN is safe.
const channel = "beacon"

// Event is a play-state change for one (user, item), broadcast to that user's
// other devices. OriginDeviceID lets a device ignore the echo of its own write.
type Event struct {
	UserID          string    `json:"userId"`
	ItemID          string    `json:"itemId"`
	PositionSeconds float64   `json:"positionSeconds"`
	DurationSeconds float64   `json:"durationSeconds,omitempty"`
	Watched         bool      `json:"watched"`
	OriginDeviceID  string    `json:"originDeviceId,omitempty"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

type subscriber struct {
	userID string
	ch     chan Event
}

// Hub fans Postgres NOTIFY play-state events out to per-user subscribers (SSE).
type Hub struct {
	pool   *pgxpool.Pool
	logger *slog.Logger

	mu     sync.Mutex
	subs   map[int]*subscriber
	nextID int
}

// NewHub returns a Beacon hub over the connection pool.
func NewHub(pool *pgxpool.Pool, logger *slog.Logger) *Hub {
	return &Hub{pool: pool, logger: logger, subs: make(map[int]*subscriber)}
}

// Publish broadcasts an event via Postgres NOTIFY; the LISTEN loop fans it out.
func (h *Hub) Publish(ctx context.Context, ev Event) error {
	payload, err := json.Marshal(ev)
	if err != nil {
		return err
	}
	_, err = h.pool.Exec(ctx, "SELECT pg_notify($1, $2)", channel, string(payload))
	return err
}

// Subscribe registers a receiver for a user's events, returning the channel and
// an unsubscribe func. The channel is buffered; a slow consumer drops events
// (it reconciles with a fetch on reconnect).
func (h *Hub) Subscribe(userID string) (<-chan Event, func()) {
	s := &subscriber{userID: userID, ch: make(chan Event, 16)}
	h.mu.Lock()
	id := h.nextID
	h.nextID++
	h.subs[id] = s
	h.mu.Unlock()
	return s.ch, func() {
		h.mu.Lock()
		delete(h.subs, id)
		h.mu.Unlock()
	}
}

// fanout delivers an event to every subscriber for its user (non-blocking).
func (h *Hub) fanout(ev Event) {
	h.mu.Lock()
	for _, s := range h.subs {
		if s.userID != ev.UserID {
			continue
		}
		select {
		case s.ch <- ev:
		default: // slow consumer: drop; it reconciles on reconnect
		}
	}
	h.mu.Unlock()
}

// Run holds a dedicated LISTEN connection and fans notifications out until ctx
// is cancelled, reconnecting with capped exponential backoff on failure.
func (h *Hub) Run(ctx context.Context) {
	backoff := time.Second
	for ctx.Err() == nil {
		if err := h.listen(ctx); err != nil && ctx.Err() == nil {
			h.logger.Warn("beacon: listen connection lost, reconnecting", "err", err, "backoff", backoff)
			select {
			case <-ctx.Done():
				return
			case <-time.After(backoff):
			}
			if backoff < 30*time.Second {
				backoff *= 2
			}
			continue
		}
		backoff = time.Second
	}
}

func (h *Hub) listen(ctx context.Context) error {
	conn, err := h.pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, "LISTEN "+channel); err != nil {
		return err
	}
	h.logger.Info("beacon: listening", "channel", channel)
	for {
		n, err := conn.Conn().WaitForNotification(ctx)
		if err != nil {
			return err
		}
		var ev Event
		if err := json.Unmarshal([]byte(n.Payload), &ev); err != nil {
			h.logger.Warn("beacon: bad payload", "err", err)
			continue
		}
		h.fanout(ev)
	}
}
