package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/google/uuid"
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

	acc, err := store.SetAccountDisabled(ctx, sessionActor(sess), memberID, true)
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
	if acc, err := store.SetAccountDisabled(ctx, sessionActor(sess), memberID, false); err != nil || acc.Disabled {
		t.Fatalf("enable = %+v, %v", acc, err)
	}
	if _, err := store.Login(ctx, email, password); err != nil {
		t.Errorf("login after re-enable: %v", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); err != nil {
		t.Errorf("device auth after re-enable: %v", err)
	}

	// Password reset: the old password stops working, the returned one signs
	// in, and the account's devices are revoked — a leaked password may
	// already have paired one.
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
	if _, err := store.AuthenticateDevice(ctx, reg.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("device auth after reset = %v, want ErrInvalidCredentials (devices revoked)", err)
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

	if _, err := store.SetAccountDisabled(ctx, sessionActor(sess), ownerID, true); !errors.Is(err, ErrOwnerAccount) {
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
	// Random really means random: this read "00000000-0000-0000-0000-000000000000"
	// until ARGY-211, and that is the one id in the estate that is NOT nowhere —
	// internal/library's stow fixture inserts an account under it, because
	// accountOf resolves an unauthenticated request to the zero uuid. Suites
	// share one database and `make test` runs packages concurrently, so the row
	// existed for the SELECT and was gone by the UPDATE, surfacing pgx.ErrNoRows.
	if _, err := store.SetAccountDisabled(ctx, sessionActor(sess), uuid.NewString(), true); !errors.Is(err, ErrNotFound) {
		t.Errorf("disable missing account = %v, want ErrNotFound", err)
	}
}

// TestDeleteAccountWithLibraries covers the legacy-data guard: ARGY-167 never
// moved libraries.account_id, so a pre-existing member can still own library
// rows, and deleting it would cascade catalog items away.
func TestDeleteAccountWithLibraries(t *testing.T) {
	store, ctx := testStore(t)
	sess, _ := ownerSession(ctx, t, store)
	member, email, _, _ := seedMember(ctx, t, store)
	memberID := member.Id.String()

	if _, err := store.pool.Exec(ctx,
		`INSERT INTO libraries (account_id, name, root_path) VALUES ($1, 'legacy', '/legacy')`, memberID); err != nil {
		t.Fatalf("seed legacy library: %v", err)
	}
	if err := store.DeleteAccount(ctx, sessionActor(sess), memberID); !errors.Is(err, ErrAccountHasLibraries) {
		t.Fatalf("delete with libraries = %v, want ErrAccountHasLibraries", err)
	}
	if _, err := store.AccountByEmail(ctx, email); err != nil {
		t.Fatalf("account should survive the refused delete: %v", err)
	}
	if _, err := store.pool.Exec(ctx, `DELETE FROM libraries WHERE account_id = $1`, memberID); err != nil {
		t.Fatalf("clear libraries: %v", err)
	}
	if err := store.DeleteAccount(ctx, sessionActor(sess), memberID); err != nil {
		t.Fatalf("delete after clearing libraries: %v", err)
	}
}

// TestAuditSurvivesCanceledContext pins the WithoutCancel fix: the client can
// disconnect (canceling the request context) between the mutation and the
// audit insert, and the trail must still get its row.
func TestAuditSurvivesCanceledContext(t *testing.T) {
	store, ctx := testStore(t)
	sess, _ := ownerSession(ctx, t, store)

	canceled, cancel := context.WithCancel(ctx)
	cancel()
	e := sessionActor(sess)
	e.action, e.targetType, e.targetID = "test.canceled_ctx", "account", sess.AccountId.String()
	store.audit(canceled, e)

	var n int
	if err := store.pool.QueryRow(ctx,
		`SELECT count(*) FROM audit_log WHERE action = 'test.canceled_ctx' AND target_id = $1`,
		sess.AccountId.String()).Scan(&n); err != nil || n != 1 {
		t.Fatalf("audit rows after canceled-context write = %d (err %v), want 1", n, err)
	}
}

// TestAccountRoutesWiring locks the mux wiring: every lifecycle route exists
// (a dropped registration would 404) and sits behind the owner gate (a
// household admin on a member account gets 403 — if a route were mistakenly
// requireAdmin-gated, this member admin would get through). The owner-passes
// half of the gate is covered by TestRequireOwner; the behavior behind the
// routes by the store tests above.
func TestAccountRoutesWiring(t *testing.T) {
	store, ctx := testStore(t)
	_, _ = ownerSession(ctx, t, store) // make sure an owner exists so the member can't be one
	_, email, password, profile := seedMember(ctx, t, store)
	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Email: email, Password: password, UserId: &profile.Id, DeviceName: "wiring-test",
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}

	mux := http.NewServeMux()
	RegisterRoutes(mux, store)
	target := uuid.NewString()
	routes := []struct{ method, path, body string }{
		{http.MethodGet, "/api/v1/auth/accounts", ""},
		{http.MethodPatch, "/api/v1/auth/accounts/" + target, `{"disabled":true}`},
		{http.MethodDelete, "/api/v1/auth/accounts/" + target, ""},
		{http.MethodPost, "/api/v1/auth/accounts/" + target + "/password-reset", ""},
	}
	for _, r := range routes {
		req := httptest.NewRequest(r.method, r.path, strings.NewReader(r.body))
		req.Header.Set("Authorization", "Bearer "+reg.Token)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		if rec.Code != http.StatusForbidden {
			t.Errorf("%s %s as member admin = %d, want 403", r.method, r.path, rec.Code)
		}

		rec = httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(r.method, r.path, strings.NewReader(r.body)))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s unauthenticated = %d, want 401", r.method, r.path, rec.Code)
		}
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

// TestProvisionRevokeAccount covers the id-keyed revoke Purser's offboard maps
// to (ARGY-187): disabling takes access away from every surface at once, and
// restoring gives it back *without* a re-pair — the property that makes revoke
// the right offboard primitive for a service holding real user state.
func TestProvisionRevokeAccount(t *testing.T) {
	store, ctx := testStore(t)
	_, _ = ownerSession(ctx, t, store)
	member, email, password, profile := seedMember(ctx, t, store)
	id := member.Id.String()

	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Email: email, Password: password, UserId: &profile.Id, DeviceName: "offboard-test",
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}

	mux := http.NewServeMux()
	RegisterProvisioning(mux, store, "sekrit")

	rec := provision(t, mux, http.MethodPatch, "/api/v1/admin/accounts/"+id, `{"disabled":true}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("revoke = %d (%s), want 200", rec.Code, rec.Body)
	}
	var acc api.AccountSummary
	if err := json.Unmarshal(rec.Body.Bytes(), &acc); err != nil || !acc.Disabled {
		t.Fatalf("revoke body = %s (err %v), want disabled", rec.Body, err)
	}
	if _, err := store.Login(ctx, email, password); !errors.Is(err, ErrAccountDisabled) {
		t.Errorf("login after revoke = %v, want ErrAccountDisabled", err)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("device auth after revoke = %v, want ErrInvalidCredentials", err)
	}

	// Re-running an offboard must be cheap: a second revoke is a no-op, not an
	// error, and must not restamp disabled_at.
	var first time.Time
	if err := store.pool.QueryRow(ctx, `SELECT disabled_at FROM accounts WHERE id = $1`, id).Scan(&first); err != nil {
		t.Fatalf("read disabled_at: %v", err)
	}
	if rec := provision(t, mux, http.MethodPatch, "/api/v1/admin/accounts/"+id, `{"disabled":true}`); rec.Code != http.StatusOK {
		t.Fatalf("repeat revoke = %d (%s), want 200", rec.Code, rec.Body)
	}
	var second time.Time
	if err := store.pool.QueryRow(ctx, `SELECT disabled_at FROM accounts WHERE id = $1`, id).Scan(&second); err != nil {
		t.Fatalf("re-read disabled_at: %v", err)
	}
	if !first.Equal(second) {
		t.Errorf("repeat revoke moved disabled_at from %v to %v", first, second)
	}

	// Restoring must bring the existing pairing back, not force a re-pair.
	if rec := provision(t, mux, http.MethodPatch, "/api/v1/admin/accounts/"+id, `{"disabled":false}`); rec.Code != http.StatusOK {
		t.Fatalf("restore = %d (%s), want 200", rec.Code, rec.Body)
	}
	if _, err := store.AuthenticateDevice(ctx, reg.Token); err != nil {
		t.Errorf("device auth after restore: %v", err)
	}

	var n int
	if err := store.pool.QueryRow(ctx,
		`SELECT count(*) FROM audit_log WHERE action IN ('account.disable', 'account.enable')
		 AND actor_type = 'provision' AND target_id = $1`, id).Scan(&n); err != nil || n != 3 {
		t.Errorf("provision-actor revoke audit rows = %d (err %v), want 3", n, err)
	}
}

// TestProvisionDeleteAccountByID covers the purge half (ARGY-187). The repeat
// call's 404 is the contract the caller reads as "nothing left to revoke", so
// it is asserted rather than merely tolerated.
func TestProvisionDeleteAccountByID(t *testing.T) {
	store, ctx := testStore(t)
	_, ownerID := ownerSession(ctx, t, store)
	member, email, _, _ := seedMember(ctx, t, store)
	id := member.Id.String()

	mux := http.NewServeMux()
	RegisterProvisioning(mux, store, "sekrit")

	if rec := provision(t, mux, http.MethodDelete, "/api/v1/admin/accounts/"+id, ""); rec.Code != http.StatusNoContent {
		t.Fatalf("delete = %d (%s), want 204", rec.Code, rec.Body)
	}
	if _, err := store.AccountByEmail(ctx, email); !errors.Is(err, ErrNotFound) {
		t.Errorf("lookup after delete = %v, want ErrNotFound", err)
	}
	if rec := provision(t, mux, http.MethodDelete, "/api/v1/admin/accounts/"+id, ""); rec.Code != http.StatusNotFound {
		t.Errorf("repeat delete = %d, want 404", rec.Code)
	}

	var n int
	if err := store.pool.QueryRow(ctx,
		`SELECT count(*) FROM audit_log WHERE action = 'account.delete' AND actor_type = 'provision' AND target_id = $1`,
		id).Scan(&n); err != nil || n != 1 {
		t.Errorf("provision-actor delete audit rows = %d (err %v), want 1", n, err)
	}

	// The owner guard has to hold on the provisioning surface too — a token
	// leak must not be able to delete the instance out from under itself.
	if rec := provision(t, mux, http.MethodDelete, "/api/v1/admin/accounts/"+ownerID, ""); rec.Code != http.StatusConflict {
		t.Errorf("delete owner = %d, want 409", rec.Code)
	}
	if rec := provision(t, mux, http.MethodPatch, "/api/v1/admin/accounts/"+ownerID, `{"disabled":true}`); rec.Code != http.StatusConflict {
		t.Errorf("revoke owner = %d, want 409", rec.Code)
	}
}

// TestProvisionAccountRoutesWiring locks the gate and the argument handling on
// the id-keyed routes: no token is 401 (not 404), and a malformed id is 400
// rather than reaching the store.
func TestProvisionAccountRoutesWiring(t *testing.T) {
	store, ctx := testStore(t)
	_, _ = ownerSession(ctx, t, store)
	member, email, _, _ := seedMember(ctx, t, store)
	id := member.Id.String()

	mux := http.NewServeMux()
	RegisterProvisioning(mux, store, "sekrit")

	routes := []struct{ method, path, body string }{
		{http.MethodPatch, "/api/v1/admin/accounts/" + id, `{"disabled":true}`},
		{http.MethodDelete, "/api/v1/admin/accounts/" + id, ""},
	}
	for _, r := range routes {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(r.method, r.path, strings.NewReader(r.body)))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s without token = %d, want 401", r.method, r.path, rec.Code)
		}

		bad := strings.Replace(r.path, id, "not-a-uuid", 1)
		if rec := provision(t, mux, r.method, bad, r.body); rec.Code != http.StatusBadRequest {
			t.Errorf("%s %s = %d, want 400", r.method, bad, rec.Code)
		}
	}

	// The released email-keyed delete shares a prefix with the new id-keyed one
	// and must keep routing to its own handler. Deleting a real account proves
	// it: had the {accountId} pattern swallowed the bare path, or the
	// registration been dropped, this would 404 instead of 204.
	if rec := provision(t, mux, http.MethodDelete, "/api/v1/admin/accounts?email="+email, ""); rec.Code != http.StatusNoContent {
		t.Errorf("email-keyed delete = %d, want 204 from its own handler", rec.Code)
	}
}

// provision issues an authorized request against the provisioning mux.
func provision(t *testing.T, mux *http.ServeMux, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("X-Provision-Token", "sekrit")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}
