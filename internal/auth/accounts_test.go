package auth

import (
	"context"
	"errors"
	"testing"

	"github.com/Einlanzerous/argosy/internal/api"
)

// seedMember provisions a member account (never the owner — ownerSession has
// already made sure one exists) and returns it with its login email, password,
// and seed profile.
func seedMember(ctx context.Context, t *testing.T, store *Store) (acc api.Account, email, password string, profile api.UserProfile) {
	t.Helper()
	email = uniqueUsername() + "@example.test"
	out, err := store.ProvisionAccount(ctx, api.AccountCreateRequest{Email: email, AccountName: "Member " + uniqueUsername()})
	if err != nil {
		t.Fatalf("provision member: %v", err)
	}
	if out.GeneratedPassword == nil {
		t.Fatal("provision returned no generated password")
	}
	login, err := store.Login(ctx, email, *out.GeneratedPassword)
	if err != nil {
		t.Fatalf("login as provisioned member: %v", err)
	}
	return out.Account, email, *out.GeneratedPassword, login.Profiles[0]
}

// ownerSession guarantees the instance has an owner and returns a session on
// some account to act as the audit actor. The store methods don't gate on the
// caller (the handlers' RequireOwner does); tests only need a plausible actor.
func ownerSession(ctx context.Context, t *testing.T, store *Store) (api.Session, string) {
	t.Helper()
	email := uniqueUsername() + "@example.test"
	acc, err := store.CreateAccount(ctx, email, "pw-"+uniqueUsername(), "Owner Household")
	if err != nil {
		t.Fatalf("create account: %v", err)
	}
	ownerID, ok, err := store.OwnerAccountID(ctx)
	if err != nil || !ok {
		t.Fatalf("owner account: ok=%v err=%v", ok, err)
	}
	profiles, err := store.profiles(ctx, acc.Id.String())
	if err != nil || len(profiles) == 0 {
		t.Fatalf("profiles: %v", err)
	}
	return api.Session{AccountId: acc.Id, UserId: profiles[0].Id}, ownerID
}

func TestAccountLifecycle(t *testing.T) {
	store, ctx := testStore(t)
	sess, _ := ownerSession(ctx, t, store)
	member, email, password, profile := seedMember(ctx, t, store)
	memberID := member.Id.String()

	// The list carries the member with its email and seed profile.
	list, err := store.ListAccounts(ctx)
	if err != nil {
		t.Fatalf("list accounts: %v", err)
	}
	var row *api.AccountSummary
	for i := range list {
		if list[i].Id == member.Id {
			row = &list[i]
		}
	}
	if row == nil {
		t.Fatalf("member %s missing from account list", memberID)
	}
	if row.Email != email || row.IsOwner || row.Disabled || row.ProfileCount != 1 {
		t.Fatalf("member row = %+v, want email=%s member enabled with 1 profile", row, email)
	}
	if !list[0].IsOwner {
		t.Errorf("list is not owner-first: first row = %+v", list[0])
	}

	// Pair a device while enabled; its token must die the moment the account is
	// disabled.
	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Email: email, Password: password, UserId: &profile.Id, DeviceName: "member phone",
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); err != nil {
		t.Fatalf("device auth while enabled: %v", err)
	}

	acc, err := store.SetAccountDisabled(ctx, sess, memberID, true)
	if err != nil || !acc.Disabled {
		t.Fatalf("disable = %+v, %v", acc, err)
	}
	if _, err := store.Login(ctx, email, password); !errors.Is(err, ErrAccountDisabled) {
		t.Errorf("login while disabled = %v, want ErrAccountDisabled", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("device auth while disabled = %v, want ErrInvalidCredentials", err)
	}
	// A wrong password must NOT reveal the disabled state.
	if _, err := store.Login(ctx, email, "not-the-password"); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("wrong password on disabled account = %v, want ErrInvalidCredentials", err)
	}

	// Re-enable restores both sign-in and the device token.
	if acc, err := store.SetAccountDisabled(ctx, sess, memberID, false); err != nil || acc.Disabled {
		t.Fatalf("enable = %+v, %v", acc, err)
	}
	if _, err := store.Login(ctx, email, password); err != nil {
		t.Errorf("login after re-enable: %v", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); err != nil {
		t.Errorf("device auth after re-enable: %v", err)
	}

	// Password reset: the old password stops working, the returned one signs in.
	reset, err := store.ResetAccountPassword(ctx, sess, memberID)
	if err != nil || reset.GeneratedPassword == "" {
		t.Fatalf("reset password = %+v, %v", reset, err)
	}
	if _, err := store.Login(ctx, email, password); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("old password after reset = %v, want ErrInvalidCredentials", err)
	}
	if _, err := store.Login(ctx, email, reset.GeneratedPassword); err != nil {
		t.Errorf("new password after reset: %v", err)
	}

	// Delete: the account and its cascade are gone.
	if err := store.DeleteAccount(ctx, sessionActor(sess), memberID); err != nil {
		t.Fatalf("delete account: %v", err)
	}
	if _, err := store.AccountByEmail(ctx, email); !errors.Is(err, ErrNotFound) {
		t.Errorf("lookup after delete = %v, want ErrNotFound", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("device auth after delete = %v, want ErrInvalidCredentials", err)
	}

	// Every step above left an audit row.
	for _, action := range []string{"account.provision", "account.disable", "account.enable", "account.password_reset", "account.delete"} {
		var n int
		if err := store.pool.QueryRow(ctx,
			`SELECT count(*) FROM audit_log WHERE action = $1 AND target_id = $2`, action, memberID).Scan(&n); err != nil {
			t.Fatalf("count audit %s: %v", action, err)
		}
		if n != 1 {
			t.Errorf("audit rows for %s = %d, want 1", action, n)
		}
	}
}

func TestAccountLifecycleOwnerGuard(t *testing.T) {
	store, ctx := testStore(t)
	sess, ownerID := ownerSession(ctx, t, store)

	if _, err := store.SetAccountDisabled(ctx, sess, ownerID, true); !errors.Is(err, ErrOwnerAccount) {
		t.Errorf("disable owner = %v, want ErrOwnerAccount", err)
	}
	if err := store.DeleteAccount(ctx, sessionActor(sess), ownerID); !errors.Is(err, ErrOwnerAccount) {
		t.Errorf("delete owner = %v, want ErrOwnerAccount", err)
	}
	if _, err := store.ResetAccountPassword(ctx, sess, ownerID); !errors.Is(err, ErrOwnerAccount) {
		t.Errorf("reset owner password = %v, want ErrOwnerAccount", err)
	}
	// And the owner is still signed-in-able and listed.
	var isOwner bool
	if err := store.pool.QueryRow(ctx, `SELECT is_owner FROM accounts WHERE id = $1`, ownerID).Scan(&isOwner); err != nil || !isOwner {
		t.Fatalf("owner row after guard tests: is_owner=%v err=%v", isOwner, err)
	}

	// A random id that exists nowhere answers not-found, not a guard error.
	if _, err := store.SetAccountDisabled(ctx, sess, "00000000-0000-0000-0000-000000000000", true); !errors.Is(err, ErrNotFound) {
		t.Errorf("disable missing account = %v, want ErrNotFound", err)
	}
}

func TestDeprovisionAccountByEmail(t *testing.T) {
	store, ctx := testStore(t)
	_, _ = ownerSession(ctx, t, store)
	member, email, _, _ := seedMember(ctx, t, store)

	if err := store.DeprovisionAccountByEmail(ctx, email); err != nil {
		t.Fatalf("deprovision: %v", err)
	}
	if _, err := store.AccountByEmail(ctx, email); !errors.Is(err, ErrNotFound) {
		t.Errorf("lookup after deprovision = %v, want ErrNotFound", err)
	}
	var n int
	if err := store.pool.QueryRow(ctx,
		`SELECT count(*) FROM audit_log WHERE action = 'account.delete' AND actor_type = 'provision' AND target_id = $1`,
		member.Id.String()).Scan(&n); err != nil || n != 1 {
		t.Errorf("provision-actor delete audit rows = %d (err %v), want 1", n, err)
	}

	if err := store.DeprovisionAccountByEmail(ctx, "nobody-"+email); !errors.Is(err, ErrNotFound) {
		t.Errorf("deprovision unknown email = %v, want ErrNotFound", err)
	}
}
