package beacon

import (
	"context"
	"io"
	"log/slog"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestFanoutScopedByUser(t *testing.T) {
	h := NewHub(nil, nil)
	aCh, aCancel := h.Subscribe("userA")
	defer aCancel()
	bCh, bCancel := h.Subscribe("userB")
	defer bCancel()

	h.fanout(Event{UserID: "userA", ItemID: "i1", PositionSeconds: 42})

	select {
	case ev := <-aCh:
		if ev.ItemID != "i1" || ev.PositionSeconds != 42 {
			t.Errorf("userA got %+v, want i1@42", ev)
		}
	case <-time.After(time.Second):
		t.Fatal("userA should have received the event")
	}

	select {
	case ev := <-bCh:
		t.Fatalf("userB should not receive userA's event, got %+v", ev)
	case <-time.After(50 * time.Millisecond):
		// expected: nothing
	}
}

func TestUnsubscribeStopsDelivery(t *testing.T) {
	h := NewHub(nil, nil)
	ch, cancel := h.Subscribe("u")
	cancel()
	h.fanout(Event{UserID: "u", ItemID: "i"})
	select {
	case _, ok := <-ch:
		if ok {
			t.Fatal("unsubscribed channel should not receive events")
		}
	case <-time.After(50 * time.Millisecond):
		// expected: no delivery
	}
}

// TestPublishDeliversOverPostgres exercises the real LISTEN/NOTIFY bus: a Run
// loop LISTENs, Publish does pg_notify, and a subscriber receives it. Runs in CI
// (ARGOSY_TEST_DATABASE_URL points at the service); skipped otherwise.
func TestPublishDeliversOverPostgres(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run the beacon integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	defer pool.Close()

	h := NewHub(pool, slog.New(slog.NewTextHandler(io.Discard, nil)))
	runCtx, stop := context.WithCancel(context.Background())
	defer stop()
	go h.Run(runCtx)

	ch, unsub := h.Subscribe("user-1")
	defer unsub()

	// Re-publish on a tick: NOTIFY only reaches listeners already LISTENing, and
	// Run establishes the LISTEN asynchronously — retrying removes the startup race.
	want := Event{UserID: "user-1", ItemID: "item-9", PositionSeconds: 123}
	deadline := time.After(10 * time.Second)
	tick := time.NewTicker(250 * time.Millisecond)
	defer tick.Stop()
	_ = h.Publish(ctx, want)
	for {
		select {
		case got := <-ch:
			if got.ItemID != "item-9" || got.PositionSeconds != 123 {
				t.Fatalf("got %+v, want item-9@123", got)
			}
			return
		case <-tick.C:
			_ = h.Publish(ctx, want)
		case <-deadline:
			t.Fatal("did not receive the published event over LISTEN/NOTIFY")
		}
	}
}

func TestSlowConsumerDoesNotBlock(t *testing.T) {
	h := NewHub(nil, nil)
	// Subscribe but never drain; fill past the buffer.
	_, cancel := h.Subscribe("u")
	defer cancel()
	done := make(chan struct{})
	go func() {
		for i := 0; i < 1000; i++ {
			h.fanout(Event{UserID: "u", ItemID: "i"})
		}
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("fanout blocked on a slow consumer")
	}
}
