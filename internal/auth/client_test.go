package auth

import (
	"strings"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
)

func TestSanitizeClient(t *testing.T) {
	if got := SanitizeClient("  argosy-web/0.32.0\r\n"); got != "argosy-web/0.32.0" {
		t.Errorf("got %q", got)
	}
	if got := SanitizeClient(strings.Repeat("a", 500)); len(got) != maxClientLen {
		t.Errorf("len = %d, want %d", len(got), maxClientLen)
	}
}

func TestClientTrackerThrottle(t *testing.T) {
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	c := &clientTracker{now: func() time.Time { return now }}
	const dev, v1, v2 = "dev-1", "argosy-android/0.32.0+78", "argosy-android/0.33.0+80"

	if c.needsWrite(dev, "", "", nil) {
		t.Error("empty client must never write")
	}
	if !c.needsWrite(dev, v1, "", nil) {
		t.Fatal("first sighting must write")
	}
	c.wrote(dev, v1)

	now = now.Add(10 * time.Minute)
	if c.needsWrite(dev, v1, v1, &now) {
		t.Error("unchanged within the hour must not write")
	}
	if !c.needsWrite(dev, v2, v1, &now) {
		t.Error("changed client must write")
	}
	c.wrote(dev, v2)

	now = now.Add(clientRefresh + time.Minute)
	if !c.needsWrite(dev, v2, v2, &now) {
		t.Error("same client after an hour must write")
	}

	// After a restart the cache is empty: fresh stored values suppress the
	// write, stale or different ones do not.
	fresh := &clientTracker{now: func() time.Time { return now }}
	stored := now.Add(-5 * time.Minute)
	if fresh.needsWrite("dev-2", v1, v1, &stored) {
		t.Error("fresh stored value should seed the cache and skip the write")
	}
	old := now.Add(-2 * time.Hour)
	if !fresh.needsWrite("dev-3", v1, v1, &old) {
		t.Error("stale stored value must write")
	}
}

func TestAuthenticateDeviceRecordsClient(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Client Household"); err != nil {
		t.Fatal(err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatal(err)
	}
	profile := login.Profiles[0].Id
	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username: &username, Password: password, UserId: &profile, DeviceName: "Pixel",
	})
	if err != nil {
		t.Fatal(err)
	}
	devID := reg.Device.Id.String()

	read := func() (client *string, at *time.Time) {
		t.Helper()
		if err := store.pool.QueryRow(ctx,
			`SELECT last_client, last_client_at FROM devices WHERE id = $1`, devID).Scan(&client, &at); err != nil {
			t.Fatal(err)
		}
		return
	}
	authWith := func(client string) *Trace {
		t.Helper()
		tr := &Trace{Client: client}
		if _, err := store.AuthenticateDevice(WithTrace(ctx, tr), reg.Token); err != nil {
			t.Fatal(err)
		}
		return tr
	}

	// No header: nothing recorded.
	authWith("")
	if c, _ := read(); c != nil {
		t.Fatalf("last_client = %q with no header, want NULL", *c)
	}

	// Identity reaches the trace.
	const v1 = "argosy-android/0.32.0+78 (Pixel 9; Android 36)"
	tr := authWith(v1)
	acc, dev, name := tr.Identity()
	if acc != login.Account.Id.String() || dev != devID || name != "Pixel" {
		t.Errorf("identity = %q %q %q", acc, dev, name)
	}
	c, at1 := read()
	if c == nil || *c != v1 || at1 == nil {
		t.Fatalf("after first sighting: %v %v", c, at1)
	}

	// Unchanged inside the hour: no write (timestamp untouched).
	time.Sleep(20 * time.Millisecond)
	authWith(v1)
	if _, at2 := read(); !at2.Equal(*at1) {
		t.Errorf("unchanged client rewrote last_client_at: %v -> %v", at1, at2)
	}

	// Changed: write.
	const v2 = "argosy-android/0.33.0+80 (Pixel 9; Android 36)"
	authWith(v2)
	c, at3 := read()
	if *c != v2 || !at3.After(*at1) {
		t.Errorf("changed client not recorded: %q %v", *c, at3)
	}

	// Same value after an hour: write. Age the in-memory stamp.
	store.clients.seen.Store(devID, clientStamp{client: v2, at: time.Now().Add(-2 * time.Hour)})
	time.Sleep(20 * time.Millisecond)
	authWith(v2)
	if _, at4 := read(); !at4.After(*at3) {
		t.Errorf("stale client was not refreshed: %v -> %v", at3, at4)
	}

	// The Fleet API exposes it.
	sess, _ := store.AuthenticateDevice(ctx, reg.Token)
	devs, err := store.ListDevices(ctx, sess)
	if err != nil || len(devs) != 1 || devs[0].LastClient == nil || *devs[0].LastClient != v2 {
		t.Errorf("ListDevices lastClient = %+v err=%v", devs, err)
	}
}
