package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/google/uuid"
)

// TestInstanceOwnership covers the ARGY-167 split: exactly one account owns the
// instance, every other account browses that account's catalog, and a household
// admin elsewhere still administers its own household.
func TestInstanceOwnership(t *testing.T) {
	store, ctx := testStore(t)

	// The test database already has an owner (the 00023 backfill, or a sibling
	// test's first account), so a newly provisioned account must not take over.
	before, hadOwner, err := store.OwnerAccountID(ctx)
	if err != nil {
		t.Fatalf("owner lookup: %v", err)
	}
	if !hadOwner {
		t.Skip("no owner in this database yet; first-account claim is covered by TestFirstAccountClaimsInstance")
	}

	email := uniqueUsername() + "@example.test"
	password := "pw-" + uniqueUsername()
	member, err := store.CreateAccount(ctx, email, password, "Member Household")
	if err != nil {
		t.Fatalf("create account: %v", err)
	}
	after, _, err := store.OwnerAccountID(ctx)
	if err != nil {
		t.Fatalf("owner lookup after create: %v", err)
	}
	if after != before {
		t.Fatalf("ownership moved to a provisioned account: %s → %s", before, after)
	}

	// A member's catalog resolves to the owner's account, not its own — this is
	// what makes the shared library visible instead of an empty one.
	catalog, err := store.CatalogAccountID(ctx, member.Id.String())
	if err != nil {
		t.Fatalf("catalog account: %v", err)
	}
	if catalog != before {
		t.Errorf("member catalog account = %s, want the owner %s", catalog, before)
	}

	// The seed profile is still a household admin: members manage their own
	// profiles/devices. Ownership is the separate axis.
	login, err := store.Login(ctx, email, password)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if len(login.Profiles) != 1 || login.Profiles[0].Role != api.Admin {
		t.Fatalf("seed profile = %+v, want one admin", login.Profiles)
	}

	// ...but the session must not claim instance ownership.
	userUUID := login.Profiles[0].Id
	reg, err := store.RegisterDevice(ctx, api.DeviceRegistrationRequest{
		Email: email, Password: password, UserId: &userUUID, DeviceName: "member-device",
	})
	if err != nil {
		t.Fatalf("register device: %v", err)
	}
	sess, err := store.AuthenticateDevice(ctx, reg.Token)
	if err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	if IsOwnerSession(sess) {
		t.Error("member session reports instance ownership")
	}
	if sess.Role != api.Admin {
		t.Errorf("member session role = %q, want admin (household admin is retained)", sess.Role)
	}
}

// TestFirstAccountClaimsInstance proves a fresh self-hosted install works out of
// the box: whoever creates the first account owns the server. Skips when the
// database already has an owner (the usual case for a shared test database).
func TestFirstAccountClaimsInstance(t *testing.T) {
	store, ctx := testStore(t)
	if _, hadOwner, err := store.OwnerAccountID(ctx); err != nil {
		t.Fatalf("owner lookup: %v", err)
	} else if hadOwner {
		t.Skip("database already has an instance owner")
	}
	email := uniqueUsername() + "@example.test"
	acc, err := store.CreateAccount(ctx, email, "pw-"+uniqueUsername(), "First Household")
	if err != nil {
		t.Fatalf("create account: %v", err)
	}
	id, ok, err := store.OwnerAccountID(ctx)
	if err != nil || !ok {
		t.Fatalf("owner after first account: ok=%v err=%v", ok, err)
	}
	if id != acc.Id.String() {
		t.Errorf("owner = %s, want the first account %s", id, acc.Id.String())
	}
}

// TestRequireOwner checks the gate on the server's own powers (library roots,
// scans): owning admin passes; a household admin on another account and a viewer
// on the owning account are both refused.
func TestRequireOwner(t *testing.T) {
	yes, no := true, false
	cases := []struct {
		name string
		sess api.Session
		want int
	}{
		{"owning admin", api.Session{Role: api.Admin, IsOwner: &yes}, http.StatusOK},
		{"owning viewer", api.Session{Role: api.Viewer, IsOwner: &yes}, http.StatusForbidden},
		{"member admin", api.Session{Role: api.Admin, IsOwner: &no}, http.StatusForbidden},
		{"member viewer", api.Session{Role: api.Viewer, IsOwner: &no}, http.StatusForbidden},
		// An older server's response has no isOwner at all; absent means false.
		{"ownership absent", api.Session{Role: api.Admin}, http.StatusForbidden},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h := RequireOwner(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(http.StatusOK)
			}))
			req := httptest.NewRequest(http.MethodPost, "/api/v1/libraries", nil)
			req = req.WithContext(context.WithValue(req.Context(), sessionKey, tc.sess))
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Errorf("status = %d, want %d", rec.Code, tc.want)
			}
		})
	}

	// No session at all (RequireOwner composed outside Middleware) is a 401.
	rec := httptest.NewRecorder()
	RequireOwner(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Error("handler ran without a session")
	})).ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/v1/libraries", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("no-session status = %d, want 401", rec.Code)
	}
}

// TestCatalogAccountFallback covers the un-owned instance: rather than serving an
// empty catalog, requests fall back to the caller's own account (pre-ARGY-167
// behavior) until an owner exists.
func TestCatalogAccountFallback(t *testing.T) {
	store, ctx := testStore(t)
	if _, hadOwner, err := store.OwnerAccountID(ctx); err != nil {
		t.Fatalf("owner lookup: %v", err)
	} else if hadOwner {
		t.Skip("database has an instance owner; fallback path not reachable")
	}
	caller := uuid.NewString()
	got, err := store.CatalogAccountID(ctx, caller)
	if err != nil {
		t.Fatalf("catalog account: %v", err)
	}
	if got != caller {
		t.Errorf("catalog account = %s, want the caller %s", got, caller)
	}
}
