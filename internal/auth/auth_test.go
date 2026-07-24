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

	start, err := store.StartLink(ctx, "", "")
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

// TestLinkPairingAnnouncedIdentity covers ARGY-123: the new device announces its
// name/platform at start, the approver sees them while pending, and approval
// uses them (unless the approver overrides the name).
func TestLinkPairingAnnouncedIdentity(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Pin Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	sess := api.Session{AccountId: login.Account.Id, UserId: login.Profiles[0].Id, Role: api.Admin}

	// Announced identity is echoed on the pending poll.
	start, err := store.StartLink(ctx, "Pixel 9", "android")
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	st, err := store.LinkStatus(ctx, start.Code)
	if err != nil || st.Status != api.Pending {
		t.Fatalf("pending poll = %+v (err %v)", st, err)
	}
	if st.DeviceName == nil || *st.DeviceName != "Pixel 9" || st.Platform == nil || *st.Platform != "android" {
		t.Fatalf("pending identity = %v/%v, want Pixel 9/android", st.DeviceName, st.Platform)
	}

	// Approval with no override adopts the announced name + platform.
	if err := store.ApproveLink(ctx, sess, start.Code, ""); err != nil {
		t.Fatalf("approve: %v", err)
	}
	if st, err = store.LinkStatus(ctx, start.Code); err != nil || st.Status != api.Approved || st.Token == nil {
		t.Fatalf("approved poll = %+v (err %v)", st, err)
	}
	devices, _ := store.ListDevices(ctx, sess)
	var paired *api.Device
	for i := range devices {
		if devices[i].Name == "Pixel 9" {
			paired = &devices[i]
		}
	}
	if paired == nil {
		t.Fatal("announced-name device not found in Fleet")
	}
	if paired.Platform == nil || *paired.Platform != "android" {
		t.Errorf("platform = %v, want android", paired.Platform)
	}

	// Approver override wins over the announced name; an unknown announced
	// platform is dropped and defaults to androidtv.
	start2, err := store.StartLink(ctx, "Mystery Box", "toaster")
	if err != nil {
		t.Fatalf("start2: %v", err)
	}
	if err := store.ApproveLink(ctx, sess, start2.Code, "Kitchen Screen"); err != nil {
		t.Fatalf("approve2: %v", err)
	}
	if st, err = store.LinkStatus(ctx, start2.Code); err != nil || st.Token == nil {
		t.Fatalf("approved poll 2 = %+v (err %v)", st, err)
	}
	devices, _ = store.ListDevices(ctx, sess)
	paired = nil
	for i := range devices {
		if devices[i].Name == "Kitchen Screen" {
			paired = &devices[i]
		}
	}
	if paired == nil {
		t.Fatal("override-name device not found in Fleet")
	}
	if paired.Platform == nil || *paired.Platform != "androidtv" {
		t.Errorf("platform = %v, want androidtv fallback", paired.Platform)
	}
}

// TestProfileManagement covers ARGY-65: the account-scoped profile CRUD plus its
// guardrails (name uniqueness, last-admin protection, self-delete, device unbind).
func TestProfileManagement(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Profiles Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatal(err)
	}
	accountID := login.Account.Id.String()
	admin := login.Profiles[0] // the bootstrap admin profile
	adminSess := api.Session{AccountId: login.Account.Id, UserId: admin.Id, Role: api.Admin}

	// Bootstrap account starts with exactly one admin, no devices.
	list, err := store.ListProfiles(ctx, accountID)
	if err != nil {
		t.Fatalf("list profiles: %v", err)
	}
	if len(list) != 1 || list[0].Role != api.Admin || list[0].DeviceCount != 0 {
		t.Fatalf("initial profiles = %+v, want one admin with 0 devices", list)
	}

	// Create a viewer profile.
	viewer, err := store.CreateProfile(ctx, accountID, "  Kids  ", api.Viewer)
	if err != nil {
		t.Fatalf("create profile: %v", err)
	}
	if viewer.Name != "Kids" || viewer.Role != api.Viewer {
		t.Errorf("created profile = %+v, want trimmed name 'Kids' / viewer", viewer)
	}

	// Validation: blank name and unknown role are rejected.
	if _, err := store.CreateProfile(ctx, accountID, "   ", api.Viewer); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("blank name: got %v, want ErrInvalidInput", err)
	}
	if _, err := store.CreateProfile(ctx, accountID, "Bogus", api.Role("wizard")); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("bad role: got %v, want ErrInvalidInput", err)
	}
	// Duplicate name (case-sensitive unique on (account, name)) conflicts.
	if _, err := store.CreateProfile(ctx, accountID, "Kids", api.Viewer); !errors.Is(err, ErrNameTaken) {
		t.Errorf("dup name: got %v, want ErrNameTaken", err)
	}

	// Rename + promote the viewer in one update.
	promoted, err := store.UpdateProfile(ctx, accountID, viewer.Id.String(), strPtr("Teens"), rolePtr(api.Admin))
	if err != nil {
		t.Fatalf("update profile: %v", err)
	}
	if promoted.Name != "Teens" || promoted.Role != api.Admin {
		t.Errorf("updated profile = %+v, want Teens/admin", promoted)
	}
	// Renaming onto an existing name conflicts.
	if _, err := store.UpdateProfile(ctx, accountID, viewer.Id.String(), strPtr(admin.Name), nil); !errors.Is(err, ErrNameTaken) {
		t.Errorf("rename collision: got %v, want ErrNameTaken", err)
	}
	// Updating an unknown profile is a not-found.
	if _, err := store.UpdateProfile(ctx, accountID, login.Account.Id.String(), strPtr("Nope"), nil); !errors.Is(err, ErrNotFound) {
		t.Errorf("update missing: got %v, want ErrNotFound", err)
	}

	// With two admins, demote the bootstrap admin to viewer (another admin remains).
	if _, err := store.UpdateProfile(ctx, accountID, admin.Id.String(), nil, rolePtr(api.Viewer)); err != nil {
		t.Fatalf("demote with spare admin: %v", err)
	}
	// Now 'Teens' is the only admin: demoting it must be refused.
	if _, err := store.UpdateProfile(ctx, accountID, viewer.Id.String(), nil, rolePtr(api.Viewer)); !errors.Is(err, ErrLastAdmin) {
		t.Errorf("demote last admin: got %v, want ErrLastAdmin", err)
	}

	// Bind a device to the (now viewer) bootstrap profile and confirm the count.
	if _, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username: username, Password: password, UserId: admin.Id, DeviceName: "Old Phone",
	}); err != nil {
		t.Fatalf("register device: %v", err)
	}
	list, _ = store.ListProfiles(ctx, accountID)
	var bootstrap api.ProfileSummary
	for _, p := range list {
		if p.Id == admin.Id {
			bootstrap = p
		}
	}
	if bootstrap.DeviceCount != 1 {
		t.Errorf("bootstrap device count = %d, want 1", bootstrap.DeviceCount)
	}

	// Delete guards: can't delete the profile you're signed in as...
	if err := store.DeleteProfile(ctx, adminSess, admin.Id.String()); !errors.Is(err, ErrSelfDelete) {
		t.Errorf("self-delete: got %v, want ErrSelfDelete", err)
	}
	// ...and can't delete the last admin ('Teens'), even from another session.
	if err := store.DeleteProfile(ctx, adminSess, viewer.Id.String()); !errors.Is(err, ErrLastAdmin) {
		t.Errorf("delete last admin: got %v, want ErrLastAdmin", err)
	}

	// Delete the bootstrap viewer from the Teens session — its device unbinds
	// (FK ON DELETE SET NULL) rather than blocking the delete.
	teenSess := api.Session{AccountId: login.Account.Id, UserId: viewer.Id, Role: api.Admin}
	if err := store.DeleteProfile(ctx, teenSess, admin.Id.String()); err != nil {
		t.Fatalf("delete profile: %v", err)
	}
	list, _ = store.ListProfiles(ctx, accountID)
	if len(list) != 1 || list[0].Id != viewer.Id {
		t.Fatalf("after delete, profiles = %+v, want only Teens", list)
	}
}

func strPtr(s string) *string      { return &s }
func rolePtr(r api.Role) *api.Role { return &r }

// TestSwitchDeviceProfile covers ARGY-85: an in-place profile switch keeps the
// device token, moves freely to a viewer profile, and gates escalation into an
// admin profile behind the account password.
func TestSwitchDeviceProfile(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Switch Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatal(err)
	}
	accountID := login.Account.Id.String()
	adminID := login.Profiles[0].Id

	// A second admin and a viewer to switch between.
	otherAdmin, err := store.CreateProfile(ctx, accountID, "Co-Admin", api.Admin)
	if err != nil {
		t.Fatalf("create co-admin: %v", err)
	}
	viewer, err := store.CreateProfile(ctx, accountID, "Kids", api.Viewer)
	if err != nil {
		t.Fatalf("create viewer: %v", err)
	}

	// Pair a device on the admin profile.
	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username: username, Password: password, UserId: adminID, DeviceName: "Phone",
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}
	sess, err := store.AuthenticateDevice(ctx, reg.Token)
	if err != nil {
		t.Fatal(err)
	}

	// Switch admin -> viewer: free (no password), token unchanged.
	newSess, err := store.SwitchDeviceProfile(ctx, sess, viewer.Id.String(), "")
	if err != nil {
		t.Fatalf("switch to viewer: %v", err)
	}
	if newSess.UserId != viewer.Id || newSess.Role != api.Viewer {
		t.Errorf("after switch session = %v/%v, want viewer", newSess.UserId, newSess.Role)
	}
	if newSess.DeviceId != sess.DeviceId {
		t.Errorf("device id changed on switch: %v -> %v", sess.DeviceId, newSess.DeviceId)
	}
	// The same token now authenticates AS the viewer (binding moved, token kept).
	reauth, err := store.AuthenticateDevice(ctx, reg.Token)
	if err != nil {
		t.Fatalf("re-auth after switch: %v", err)
	}
	if reauth.UserId != viewer.Id || reauth.Role != api.Viewer {
		t.Errorf("token now resolves to %v/%v, want viewer", reauth.UserId, reauth.Role)
	}

	// From the viewer session, escalating to an admin profile needs the password.
	viewerSess := reauth
	if _, err := store.SwitchDeviceProfile(ctx, viewerSess, otherAdmin.Id.String(), ""); !errors.Is(err, ErrPasswordRequired) {
		t.Errorf("escalate without password: got %v, want ErrPasswordRequired", err)
	}
	if _, err := store.SwitchDeviceProfile(ctx, viewerSess, otherAdmin.Id.String(), "wrong"); !errors.Is(err, ErrWrongPassword) {
		t.Errorf("escalate with wrong password: got %v, want ErrWrongPassword", err)
	}
	adminSess, err := store.SwitchDeviceProfile(ctx, viewerSess, otherAdmin.Id.String(), password)
	if err != nil {
		t.Fatalf("escalate with correct password: %v", err)
	}
	if adminSess.UserId != otherAdmin.Id || adminSess.Role != api.Admin {
		t.Errorf("after escalation session = %v/%v, want co-admin/admin", adminSess.UserId, adminSess.Role)
	}

	// Switching to a profile outside the account is a not-found.
	if _, err := store.SwitchDeviceProfile(ctx, adminSess, login.Account.Id.String(), ""); !errors.Is(err, ErrNotFound) {
		t.Errorf("switch to foreign id: got %v, want ErrNotFound", err)
	}
}

// TestChangePassword covers ARGY-156: self-serve rotation verifies the current
// password, enforces a minimum length, and leaves device tokens signed in.
func TestChangePassword(t *testing.T) {
	store, ctx := testStore(t)
	username := uniqueUsername()
	password := "pw-" + uniqueUsername()
	if _, err := store.CreateAccount(ctx, username, password, "Rotate Household"); err != nil {
		t.Fatalf("create account: %v", err)
	}
	login, err := store.Login(ctx, username, password)
	if err != nil {
		t.Fatal(err)
	}
	accountID := login.Account.Id.String()
	newPassword := "np-" + uniqueUsername()

	// Pair a device first so we can prove rotation doesn't sign it out.
	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Username: username, Password: password, UserId: login.Profiles[0].Id, DeviceName: "Phone",
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}

	if err := store.ChangePassword(ctx, accountID, "wrong", newPassword); !errors.Is(err, ErrWrongPassword) {
		t.Errorf("wrong current password: got %v, want ErrWrongPassword", err)
	}
	if err := store.ChangePassword(ctx, accountID, password, "short"); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("too-short new password: got %v, want ErrInvalidInput", err)
	}
	// Neither failed attempt may have touched the hash.
	if _, err := store.Login(ctx, username, password); err != nil {
		t.Fatalf("login with old password after failed attempts: %v", err)
	}

	if err := store.ChangePassword(ctx, accountID, password, newPassword); err != nil {
		t.Fatalf("change password: %v", err)
	}
	if _, err := store.Login(ctx, username, password); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("login with old password: got %v, want ErrInvalidCredentials", err)
	}
	if _, err := store.Login(ctx, username, newPassword); err != nil {
		t.Errorf("login with new password: %v", err)
	}
	// The device token predates the rotation and must still authenticate.
	if _, err := store.AuthenticateDevice(ctx, reg.Token); err != nil {
		t.Errorf("device token after rotation: %v", err)
	}
}
