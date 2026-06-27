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
	// Caption position (ARGY-60) round-trips.
	pos := api.DevicePreferencesCaptionPosition("higher")
	saved, err = store.SetDevicePreferences(ctx, reg.Device.Id.String(),
		api.DevicePreferences{SubtitleEnabled: true, CaptionPosition: &pos})
	if err != nil {
		t.Fatalf("set prefs (caption position): %v", err)
	}
	if saved.CaptionPosition == nil || *saved.CaptionPosition != pos {
		t.Errorf("saved caption position = %v, want higher", saved.CaptionPosition)
	}

	if err := store.RevokeDevice(ctx, sess, reg.Device.Id); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("after revoke: got %v, want ErrInvalidCredentials", err)
	}
}

// TestDeviceInstallIdDedup covers ARGY-99: a re-pair carrying the same install
// id reuses (and un-revokes) the existing device row with a fresh token instead
// of piling up duplicates; a missing install id still gets its own row.
func TestDeviceInstallIdDedup(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Dedup Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	profile := login.Profiles[0].Id

	install := "install-" + uniqueUsername()
	reg := func(name string, installID *string) api.DeviceRegistrationResponse {
		t.Helper()
		r, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
			Username: username, Password: password, UserId: profile,
			DeviceName: name, InstallId: installID,
		})
		if err != nil {
			t.Fatalf("register %q: %v", name, err)
		}
		return r
	}
	adminSess := api.Session{AccountId: login.Account.Id, UserId: profile, Role: api.Admin}

	// First pair, then a re-pair with the same install id.
	first := reg("Phone", &install)
	second := reg("Phone (re-paired)", &install)

	// Same physical install ⇒ same device row, not a new one.
	if first.Device.Id != second.Device.Id {
		t.Fatalf("re-pair created a new row: %v != %v", first.Device.Id, second.Device.Id)
	}
	// The re-pair rotates the token: the old one stops working, the new one works.
	if _, err := store.AuthenticateDevice(ctx, first.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("stale token after re-pair: got %v, want ErrInvalidCredentials", err)
	}
	if _, err := store.AuthenticateDevice(ctx, second.Token); err != nil {
		t.Errorf("fresh token after re-pair: %v", err)
	}
	// Fleet shows exactly one (active) device for this install.
	if devices, err := store.ListDevices(ctx, adminSess); err != nil {
		t.Fatalf("list: %v", err)
	} else if len(devices) != 1 || devices[0].Revoked {
		t.Fatalf("expected one active device after re-pair, got %+v", devices)
	}
	// The latest name wins (the upsert updates it).
	if devices, _ := store.ListDevices(ctx, adminSess); devices[0].Name != "Phone (re-paired)" {
		t.Errorf("device name = %q, want the re-paired name", devices[0].Name)
	}

	// Revoke, then re-pair the same install: the row is reused and un-revoked.
	if err := store.RevokeDevice(ctx, adminSess, second.Device.Id); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	third := reg("Phone (back)", &install)
	if third.Device.Id != second.Device.Id {
		t.Errorf("re-pair after revoke made a new row: %v != %v", third.Device.Id, second.Device.Id)
	}
	if _, err := store.AuthenticateDevice(ctx, third.Token); err != nil {
		t.Errorf("token after un-revoke: %v", err)
	}

	// A registration with no install id keeps the legacy insert-every-time path.
	noInstallA := reg("Browser A", nil)
	noInstallB := reg("Browser B", nil)
	if noInstallA.Device.Id == noInstallB.Device.Id {
		t.Errorf("nil install id should not dedup, got same row %v", noInstallA.Device.Id)
	}
}

// TestLinkPairing covers ARGY-112: a TV starts a code, an authenticated session
// approves it, and the TV claims a working device token exactly once.
func TestLinkPairing(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Link Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	profile := login.Profiles[0].Id
	sess := api.Session{AccountId: login.Account.Id, UserId: profile, Role: api.Admin}

	start, err := store.StartLink(ctx)
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	if len(start.Code) != 6 {
		t.Fatalf("code = %q, want 6 chars", start.Code)
	}

	// Pending before approval.
	if st, err := store.LinkStatus(ctx, start.Code); err != nil || st.Status != api.Pending || st.Token != nil {
		t.Fatalf("pending poll = %+v (err %v)", st, err)
	}

	// The signed-in user approves the code.
	if err := store.ApproveLink(ctx, sess, start.Code, "Den TV"); err != nil {
		t.Fatalf("approve: %v", err)
	}
	// A second approval is rejected.
	if err := store.ApproveLink(ctx, sess, start.Code, "x"); !errors.Is(err, ErrLinkAlreadyClaimed) {
		t.Fatalf("double approve = %v, want ErrLinkAlreadyClaimed", err)
	}

	// Approved poll returns a token bound to the approving account + profile.
	st, err := store.LinkStatus(ctx, start.Code)
	if err != nil || st.Status != api.Approved || st.Token == nil || *st.Token == "" {
		t.Fatalf("approved poll = %+v (err %v)", st, err)
	}
	tvSess, err := store.AuthenticateDevice(ctx, *st.Token)
	if err != nil {
		t.Fatalf("authenticate paired token: %v", err)
	}
	if tvSess.AccountId != login.Account.Id || tvSess.UserId != profile {
		t.Errorf("paired session = %+v, want account/profile match", tvSess)
	}

	// The code is single-use: consumed by the approved poll.
	if _, err := store.LinkStatus(ctx, start.Code); !errors.Is(err, ErrLinkNotFound) {
		t.Fatalf("post-claim poll = %v, want ErrLinkNotFound", err)
	}
	// Unknown codes are not found.
	if _, err := store.LinkStatus(ctx, "ZZZZZZ"); !errors.Is(err, ErrLinkNotFound) {
		t.Fatalf("unknown code = %v, want ErrLinkNotFound", err)
	}

	// The TV joined the Fleet with its name + platform.
	devices, _ := store.ListDevices(ctx, sess)
	var paired *api.Device
	for i := range devices {
		if devices[i].Name == "Den TV" {
			paired = &devices[i]
		}
	}
	if paired == nil {
		t.Fatal("paired TV not found in Fleet")
	}
	if paired.Platform == nil || *paired.Platform != "androidtv" {
		t.Errorf("platform = %v, want androidtv", paired.Platform)
	}
}
