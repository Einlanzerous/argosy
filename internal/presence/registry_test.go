package presence

import (
	"testing"
	"time"
)

func TestHeartbeatDedupesByUserDeviceItem(t *testing.T) {
	r := NewRegistry(time.Minute)
	base := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	r.clock = func() time.Time { return base }

	s := Session{AccountID: "acc", UserID: "u1", DeviceID: "d1", ItemID: "i1", PositionSeconds: 10}
	first := r.Heartbeat(s)
	if first.State != StatePlaying {
		t.Errorf("state = %q, want playing", first.State)
	}

	// A later beat for the same (user,device,item) refreshes — not a duplicate.
	r.clock = func() time.Time { return base.Add(20 * time.Second) }
	s.PositionSeconds = 30
	second := r.Heartbeat(s)
	if got := len(r.Active("acc")); got != 1 {
		t.Fatalf("active = %d, want 1 (deduped)", got)
	}
	if second.PositionSeconds != 30 {
		t.Errorf("position = %v, want 30", second.PositionSeconds)
	}
	if !second.StartedAt.Equal(first.StartedAt) {
		t.Errorf("StartedAt changed across beats: %v != %v", second.StartedAt, first.StartedAt)
	}
	if !second.LastSeen.After(first.LastSeen) {
		t.Errorf("LastSeen should advance: %v not after %v", second.LastSeen, first.LastSeen)
	}
}

func TestActiveScopingAndReap(t *testing.T) {
	r := NewRegistry(30 * time.Second)
	base := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	r.clock = func() time.Time { return base }

	// Two users in one account on different devices/items + a third account.
	r.Heartbeat(Session{AccountID: "acc", UserID: "u1", DeviceID: "d1", ItemID: "i1"})
	r.Heartbeat(Session{AccountID: "acc", UserID: "u2", DeviceID: "d2", ItemID: "i2"})
	r.Heartbeat(Session{AccountID: "other", UserID: "u9", DeviceID: "d9", ItemID: "i9"})

	if got := len(r.Active("acc")); got != 2 {
		t.Errorf("account active = %d, want 2", got)
	}
	if got := len(r.ActiveForUser("u1")); got != 1 {
		t.Errorf("user active = %d, want 1", got)
	}

	// Advance past the TTL with no fresh beats → all reaped.
	r.clock = func() time.Time { return base.Add(31 * time.Second) }
	r.reap()
	if got := len(r.Active("acc")); got != 0 {
		t.Errorf("after reap active = %d, want 0", got)
	}
}

func TestCloseRemovesSession(t *testing.T) {
	r := NewRegistry(time.Minute)
	r.Heartbeat(Session{AccountID: "acc", UserID: "u1", DeviceID: "d1", ItemID: "i1"})
	r.Close("u1", "d1", "i1")
	if got := len(r.Active("acc")); got != 0 {
		t.Errorf("after close active = %d, want 0", got)
	}
}
