package auth

import (
	"context"
	"errors"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func testStore(t *testing.T) (*Store, context.Context) {
	t.Helper()
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run auth tests")
	}
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return NewStore(pool), ctx
}

func uniqueUsername() string {
	return "test_" + strconv.FormatInt(time.Now().UnixNano(), 36)
}

func TestUserPreferences(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Prefs Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatal(err)
	}
	userID := login.Profiles[0].Id.String()

	// Default is discovery when nothing saved.
	if p, err := store.GetUserPreferences(ctx, userID); err != nil || p.HomeLayout != api.Discovery {
		t.Fatalf("default = %+v (err %v), want discovery", p, err)
	}
	// Set focused, read it back.
	if p, err := store.SetUserPreferences(ctx, userID, api.UserPreferences{HomeLayout: api.Focused}); err != nil || p.HomeLayout != api.Focused {
		t.Fatalf("set focused = %+v (err %v)", p, err)
	}
	if p, _ := store.GetUserPreferences(ctx, userID); p.HomeLayout != api.Focused {
		t.Errorf("after set, layout = %q, want focused", p.HomeLayout)
	}
	// An invalid layout falls back to discovery rather than violating the CHECK.
	if p, err := store.SetUserPreferences(ctx, userID, api.UserPreferences{HomeLayout: "nonsense"}); err != nil || p.HomeLayout != api.Discovery {
		t.Errorf("invalid layout = %+v (err %v), want discovery", p, err)
	}
}

func TestAuthFlow(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername() // computed, not a static secret

	if _, err := store.CreateAccount(ctx, username, password, "Test Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}

	if _, err := store.Login(ctx, username, "wrong"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("login wrong pw: got %v, want ErrInvalidCredentials", err)
	}
	if _, err := store.Login(ctx, "ghost_"+username, password); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("login unknown user: got %v, want ErrInvalidCredentials", err)
	}

	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if len(login.Profiles) != 1 || login.Profiles[0].Role != api.Admin {
		t.Fatalf("expected one admin profile, got %+v", login.Profiles)
	}
	adminProfile := login.Profiles[0].Id

	platform := "tv"
	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username:   username,
		Password:   password,
		UserId:     adminProfile,
		DeviceName: "Test TV",
		Platform:   &platform,
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}
	if reg.Token == "" {
		t.Fatal("expected a device token")
	}

	sess, err := store.AuthenticateDevice(ctx, reg.Token)
	if err != nil {
		t.Fatalf("authenticate device: %v", err)
	}
	if sess.AccountId != login.Account.Id {
		t.Errorf("session account = %v, want %v", sess.AccountId, login.Account.Id)
	}
	if sess.UserId != adminProfile || sess.Role != api.Admin {
		t.Errorf("session user/role = %v/%v, want %v/admin", sess.UserId, sess.Role, adminProfile)
	}

	if _, err := store.AuthenticateDevice(ctx, "not-a-real-token"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("bad token: got %v, want ErrInvalidCredentials", err)
	}

	devices, err := store.ListDevices(ctx, sess)
	if err != nil {
		t.Fatalf("list devices: %v", err)
	}
	if len(devices) != 1 || devices[0].Revoked {
		t.Fatalf("expected one active device, got %+v", devices)
	}
	if devices[0].Platform == nil || *devices[0].Platform != "tv" {
		t.Errorf("device platform = %v, want tv", devices[0].Platform)
	}
	if devices[0].UserName == nil || *devices[0].UserName == "" {
		t.Errorf("device should carry its owner profile name, got %v", devices[0].UserName)
	}

	renamed, err := store.RenameDevice(ctx, sess, reg.Device.Id, "Living Room TV")
	if err != nil {
		t.Fatalf("rename device: %v", err)
	}
	if renamed.Name != "Living Room TV" {
		t.Errorf("renamed device name = %q, want Living Room TV", renamed.Name)
	}

	// Device preferences: default to subtitles off, then round-trip a save.
	defPrefs, err := store.GetDevicePreferences(ctx, reg.Device.Id.String())
	if err != nil {
		t.Fatalf("get prefs: %v", err)
	}
	if defPrefs.SubtitleEnabled {
		t.Error("default preferences should have subtitles off")
	}
	// Series auto-advance defaults ON (ARGY-89) even before any row is written.
	if defPrefs.SeriesAutoAdvance == nil || !*defPrefs.SeriesAutoAdvance {
		t.Errorf("default series auto-advance = %v, want on", defPrefs.SeriesAutoAdvance)
	}
	lang := "en"
	saved, err := store.SetDevicePreferences(ctx, reg.Device.Id.String(),
		api.DevicePreferences{SubtitleEnabled: true, SubtitleLanguage: &lang})
	if err != nil {
		t.Fatalf("set prefs: %v", err)
	}
	if !saved.SubtitleEnabled || saved.SubtitleLanguage == nil || *saved.SubtitleLanguage != "en" {
		t.Errorf("saved prefs = %+v, want subtitles on / en", saved)
	}
	// A save that omits seriesAutoAdvance keeps it on (no accidental disable).
	if saved.SeriesAutoAdvance == nil || !*saved.SeriesAutoAdvance {
		t.Errorf("after save omitting auto-advance = %v, want still on", saved.SeriesAutoAdvance)
	}
	// Explicitly turning it off round-trips and leaves the subtitle choice intact.
	off := false
	saved, err = store.SetDevicePreferences(ctx, reg.Device.Id.String(),
		api.DevicePreferences{SubtitleEnabled: true, SubtitleLanguage: &lang, SeriesAutoAdvance: &off})
	if err != nil {
		t.Fatalf("set prefs (auto-advance off): %v", err)
	}
	if saved.SeriesAutoAdvance == nil || *saved.SeriesAutoAdvance {
		t.Errorf("after disabling = %v, want off", saved.SeriesAutoAdvance)
	}
	if !saved.SubtitleEnabled {
		t.Error("disabling auto-advance should not clobber the subtitle setting")
	}

	if err := store.RevokeDevice(ctx, sess, reg.Device.Id); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("after revoke: got %v, want ErrInvalidCredentials", err)
	}
}
