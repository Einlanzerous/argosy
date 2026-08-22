package auth

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/google/uuid"
)

type ctxKey int

const (
	sessionKey ctxKey = iota
	// catalogKey holds the account whose libraries this request browses — the
	// instance owner's (ARGY-167). Resolved once per request by Middleware so
	// catalog handlers can read it as cheaply as the session.
	catalogKey
)

// RegisterRoutes wires the auth endpoints (the OpenAPI auth surface) onto mux.
func RegisterRoutes(mux *http.ServeMux, store *Store) {
	mux.HandleFunc("POST /api/v1/auth/login", handleLogin(store))
	mux.HandleFunc("POST /api/v1/auth/devices", handleRegisterDevice(store))
	mux.Handle("GET /api/v1/auth/devices", requireAuth(store, handleListDevices(store)))
	mux.Handle("DELETE /api/v1/auth/devices/{deviceId}", requireAuth(store, handleRevokeDevice(store)))
	mux.Handle("PATCH /api/v1/auth/devices/{deviceId}", requireAuth(store, handleRenameDevice(store)))
	mux.Handle("POST /api/v1/auth/devices/switch", requireAuth(store, handleSwitchDeviceProfile(store)))
	mux.Handle("GET /api/v1/auth/me", requireAuth(store, handleMe()))
	// Self-serve change-password (ARGY-156). Any signed-in profile may rotate the
	// account password — proving the current password is the credential that
	// matters (it already grants admin via the profile-switch escalation).
	mux.Handle("POST /api/v1/auth/password", requireAuth(store, handleChangePassword(store)))
	// Profile management (ARGY-65): any signed-in profile may list; create/edit/
	// delete are admin-gated.
	mux.Handle("GET /api/v1/auth/profiles", requireAuth(store, handleListProfiles(store)))
	mux.Handle("POST /api/v1/auth/profiles", requireAdmin(store, handleCreateProfile(store)))
	mux.Handle("PATCH /api/v1/auth/profiles/{userId}", requireAdmin(store, handleUpdateProfile(store)))
	mux.Handle("DELETE /api/v1/auth/profiles/{userId}", requireAdmin(store, handleDeleteProfile(store)))
	// Account lifecycle (ARGY-86): accounts are the server's households, so
	// managing them is the instance owner's power (ARGY-167), not household
	// admin's.
	mux.Handle("GET /api/v1/auth/accounts", requireOwner(store, handleListAccounts(store)))
	mux.Handle("PATCH /api/v1/auth/accounts/{accountId}", requireOwner(store, handleUpdateAccount(store, sessionActorOf)))
	mux.Handle("DELETE /api/v1/auth/accounts/{accountId}", requireOwner(store, handleDeleteAccount(store, sessionActorOf)))
	mux.Handle("POST /api/v1/auth/accounts/{accountId}/password-reset", requireOwner(store, handleResetAccountPassword(store)))
	// Device code-pairing (ARGY-112, PIN-first ARGY-123): start + poll are
	// unauthenticated (a device with no session yet); approve is any
	// authenticated user (web or mobile) blessing the code.
	mux.HandleFunc("POST /api/v1/auth/link/start", handleStartLink(store))
	mux.HandleFunc("GET /api/v1/auth/link/{code}", handleLinkStatus(store))
	mux.Handle("POST /api/v1/auth/link/{code}/approve", requireAuth(store, handleApproveLink(store)))
	mux.Handle("GET /api/v1/preferences", requireAuth(store, handleGetPreferences(store)))
	mux.Handle("PUT /api/v1/preferences", requireAuth(store, handleSetPreferences(store)))
	mux.Handle("GET /api/v1/user/preferences", requireAuth(store, handleGetUserPreferences(store)))
	mux.Handle("PUT /api/v1/user/preferences", requireAuth(store, handleSetUserPreferences(store)))
}

// RegisterProvisioning wires the service-to-service account-creation endpoint
// (ARGY-132, Purser). A bearer session can't authorize creating a *new*
// account — it is always scoped to an existing one — so this route is gated
// on the static provisioning token instead. Callers register it only when a
// token is configured; otherwise the route doesn't exist and answers 404.
func RegisterProvisioning(mux *http.ServeMux, store *Store, token string) {
	mux.Handle("POST /api/v1/admin/accounts", requireProvisionToken(token, handleCreateAccount(store)))
	mux.Handle("GET /api/v1/admin/accounts", requireProvisionToken(token, handleLookupAccount(store)))
	mux.Handle("DELETE /api/v1/admin/accounts", requireProvisionToken(token, handleDeprovisionAccount(store)))
	// Taking access away, keyed by the account id the caller recorded at
	// creation (ARGY-187). These reuse the owner routes' handlers with the
	// provisioning actor: one code path, two ways of proving you may call it.
	mux.Handle("PATCH /api/v1/admin/accounts/{accountId}", requireProvisionToken(token, handleUpdateAccount(store, provisionActorOf)))
	mux.Handle("DELETE /api/v1/admin/accounts/{accountId}", requireProvisionToken(token, handleDeleteAccount(store, provisionActorOf)))
}

// actorOf names the audit actor behind a lifecycle request. The same handler
// serves the owner's session-gated routes and the provisioning token's, and
// this is the only thing that differs between them — so the trail records
// which one actually made the change instead of attributing Purser's offboards
// to nobody.
type actorOf func(*http.Request) auditEntry

func sessionActorOf(r *http.Request) auditEntry {
	sess, _ := SessionFromContext(r.Context())
	return sessionActor(sess)
}

func provisionActorOf(*http.Request) auditEntry { return provisionActor() }

func requireProvisionToken(token string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got := r.Header.Get("X-Provision-Token")
		if got == "" || subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
			httpx.Error(w, http.StatusUnauthorized, "invalid provisioning token")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func handleCreateAccount(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req api.AccountCreateRequest
		if !decode(w, r, &req) {
			return
		}
		out, err := store.ProvisionAccount(r.Context(), req)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusCreated, out)
	}
}

// handleLookupAccount is the read-only companion to handleCreateAccount
// (ARGY-163): a reconcile pass asks "does this email have an account?" and
// must never create one as a side effect.
func handleLookupAccount(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		acc, err := store.AccountByEmail(r.Context(), r.URL.Query().Get("email"))
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, api.AccountLookupResponse{Account: acc})
	}
}

// handleDeprovisionAccount is the teardown companion to handleCreateAccount
// (ARGY-86): the provisioning service offboards a member by the same key it
// provisioned them under — their email. The owner guard answers 409.
func handleDeprovisionAccount(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := store.DeprovisionAccountByEmail(r.Context(), r.URL.Query().Get("email")); err != nil {
			writeAuthError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleListAccounts(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		accounts, err := store.ListAccounts(r.Context())
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusOK, accounts)
	}
}

// handleUpdateAccount disables or restores an account. Behind the owner gate
// it is the household-management switch; behind the provisioning token it is
// the revoke an offboard maps to (ARGY-187), which is the reversible primitive
// callers should reach for before handleDeleteAccount's cascade.
func handleUpdateAccount(store *Store, actor actorOf) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := uuid.Parse(r.PathValue("accountId"))
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid account id")
			return
		}
		var req api.AccountUpdateRequest
		if !decode(w, r, &req) {
			return
		}
		acc, err := store.SetAccountDisabled(r.Context(), actor(r), id.String(), req.Disabled)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, acc)
	}
}

// handleDeleteAccount purges an account and everything cascading from it. A
// repeat call answers 404 — already gone reads as done to a caller reconciling
// state (ARGY-187), which is what makes a re-run of an offboard cheap.
func handleDeleteAccount(store *Store, actor actorOf) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := uuid.Parse(r.PathValue("accountId"))
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid account id")
			return
		}
		if err := store.DeleteAccount(r.Context(), actor(r), id.String()); err != nil {
			writeAuthError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleResetAccountPassword(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		id, err := uuid.Parse(r.PathValue("accountId"))
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid account id")
			return
		}
		out, err := store.ResetAccountPassword(r.Context(), sess, id.String())
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, out)
	}
}

func handleGetPreferences(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		p, err := store.GetDevicePreferences(r.Context(), sess.DeviceId.String())
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusOK, p)
	}
}

func handleSetPreferences(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		var p api.DevicePreferences
		if !decode(w, r, &p) {
			return
		}
		out, err := store.SetDevicePreferences(r.Context(), sess.DeviceId.String(), p)
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusOK, out)
	}
}

func handleGetUserPreferences(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		p, err := store.GetUserPreferences(r.Context(), sess.UserId.String())
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusOK, p)
	}
}

func handleSetUserPreferences(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		var p api.UserPreferences
		if !decode(w, r, &p) {
			return
		}
		out, err := store.SetUserPreferences(r.Context(), sess.UserId.String(), p)
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusOK, out)
	}
}

func handleLogin(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req api.LoginRequest
		if !decode(w, r, &req) {
			return
		}
		resp, err := store.Login(r.Context(), credential(req.Email, req.Username), req.Password)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, resp)
	}
}

func handleRegisterDevice(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req api.DeviceRegistrationRequest
		if !decode(w, r, &req) {
			return
		}
		resp, err := store.RegisterDevice(r.Context(), req)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusCreated, resp)
	}
}

func handleListDevices(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		devices, err := store.ListDevices(r.Context(), sess)
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		if devices == nil {
			devices = []api.Device{}
		}
		httpx.JSON(w, http.StatusOK, devices)
	}
}

func handleRevokeDevice(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		id, err := uuid.Parse(r.PathValue("deviceId"))
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid device id")
			return
		}
		if err := store.RevokeDevice(r.Context(), sess, id); err != nil {
			writeAuthError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleRenameDevice(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		id, err := uuid.Parse(r.PathValue("deviceId"))
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid device id")
			return
		}
		var req api.DeviceRenameRequest
		if !decode(w, r, &req) {
			return
		}
		name := strings.TrimSpace(req.Name)
		if name == "" {
			httpx.Error(w, http.StatusBadRequest, "name is required")
			return
		}
		dev, err := store.RenameDevice(r.Context(), sess, id, name)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, dev)
	}
}

func handleListProfiles(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		profiles, err := store.ListProfiles(r.Context(), sess.AccountId.String())
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusOK, profiles)
	}
}

func handleCreateProfile(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		var req api.ProfileCreateRequest
		if !decode(w, r, &req) {
			return
		}
		p, err := store.CreateProfile(r.Context(), sess.AccountId.String(), req.Name, req.Role)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		e := sessionActor(sess)
		e.action, e.targetType, e.targetID = "profile.create", "profile", p.Id.String()
		e.detail = map[string]any{"name": p.Name, "role": p.Role}
		store.audit(r.Context(), e)
		httpx.JSON(w, http.StatusCreated, p)
	}
}

func handleUpdateProfile(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		id, err := uuid.Parse(r.PathValue("userId"))
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid profile id")
			return
		}
		var req api.ProfileUpdateRequest
		if !decode(w, r, &req) {
			return
		}
		p, err := store.UpdateProfile(r.Context(), sess.AccountId.String(), id.String(), req.Name, req.Role)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		e := sessionActor(sess)
		e.action, e.targetType, e.targetID = "profile.update", "profile", p.Id.String()
		e.detail = map[string]any{"name": p.Name, "role": p.Role}
		store.audit(r.Context(), e)
		httpx.JSON(w, http.StatusOK, p)
	}
}

func handleDeleteProfile(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		id, err := uuid.Parse(r.PathValue("userId"))
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid profile id")
			return
		}
		if err := store.DeleteProfile(r.Context(), sess, id.String()); err != nil {
			writeAuthError(w, err)
			return
		}
		e := sessionActor(sess)
		e.action, e.targetType, e.targetID = "profile.delete", "profile", id.String()
		store.audit(r.Context(), e)
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleSwitchDeviceProfile(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		var req api.DeviceSwitchRequest
		if !decode(w, r, &req) {
			return
		}
		password := ""
		if req.Password != nil {
			password = *req.Password
		}
		newSess, err := store.SwitchDeviceProfile(r.Context(), sess, req.UserId.String(), password)
		if err != nil {
			writeAuthError(w, err)
			return
		}
		httpx.JSON(w, http.StatusOK, newSess)
	}
}

func handleChangePassword(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		var req api.PasswordChangeRequest
		if !decode(w, r, &req) {
			return
		}
		if err := store.ChangePassword(r.Context(), sess.AccountId.String(), req.CurrentPassword, req.NewPassword); err != nil {
			writeAuthError(w, err)
			return
		}
		e := sessionActor(sess)
		e.action, e.targetType, e.targetID = "account.password_change", "account", sess.AccountId.String()
		store.audit(r.Context(), e)
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleMe() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		httpx.JSON(w, http.StatusOK, sess)
	}
}

func handleStartLink(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// The body (device identity) is optional; ignore a decode miss so old
		// clients that POST nothing keep working.
		var req api.LinkStartRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		name, platform := "", ""
		if req.DeviceName != nil {
			name = *req.DeviceName
		}
		if req.Platform != nil {
			platform = *req.Platform
		}
		resp, err := store.StartLink(r.Context(), name, platform)
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusCreated, resp)
	}
}

func handleLinkStatus(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		resp, err := store.LinkStatus(r.Context(), r.PathValue("code"))
		if errors.Is(err, ErrLinkNotFound) {
			httpx.Error(w, http.StatusNotFound, "not found")
			return
		}
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal error")
			return
		}
		httpx.JSON(w, http.StatusOK, resp)
	}
}

func handleApproveLink(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		// The body (a device name) is optional; ignore a decode miss.
		var req api.LinkApproveRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		name := ""
		if req.DeviceName != nil {
			name = *req.DeviceName
		}
		err := store.ApproveLink(r.Context(), sess, r.PathValue("code"), name)
		switch {
		case errors.Is(err, ErrLinkNotFound):
			httpx.Error(w, http.StatusNotFound, "not found")
		case errors.Is(err, ErrLinkAlreadyClaimed):
			httpx.Error(w, http.StatusConflict, "already approved")
		case err != nil:
			httpx.Error(w, http.StatusInternalServerError, "internal error")
		default:
			w.WriteHeader(http.StatusNoContent)
		}
	}
}

// Middleware authenticates the bearer token and injects the session into the
// request context (read it with SessionFromContext). 401 on missing/invalid.
func Middleware(store *Store) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token := bearerToken(r)
			if token == "" {
				httpx.Error(w, http.StatusUnauthorized, "missing bearer token")
				return
			}
			sess, err := store.AuthenticateDevice(r.Context(), token)
			if err != nil {
				httpx.Error(w, http.StatusUnauthorized, "invalid or revoked token")
				return
			}
			// Resolve the catalog account (the instance owner's) alongside the
			// session so browse handlers never have to hit the database for it.
			catalog, err := store.CatalogAccountID(r.Context(), sess.AccountId.String())
			if err != nil {
				httpx.Error(w, http.StatusInternalServerError, "internal error")
				return
			}
			ctx := context.WithValue(r.Context(), sessionKey, sess)
			ctx = context.WithValue(ctx, catalogKey, catalog)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func requireAuth(store *Store, next http.HandlerFunc) http.Handler {
	return Middleware(store)(next)
}

// requireAdmin authenticates then gates on the admin role (RequireAdmin reads the
// session Middleware injects, so it must be composed inside it).
func requireAdmin(store *Store, next http.HandlerFunc) http.Handler {
	return Middleware(store)(RequireAdmin(next))
}

// requireOwner authenticates then gates on instance ownership (ARGY-167).
func requireOwner(store *Store, next http.HandlerFunc) http.Handler {
	return Middleware(store)(RequireOwner(next))
}

// RequireAdmin wraps next so only an admin session reaches it; a viewer gets
// 403. It must be composed *inside* Middleware (it reads the session from the
// context Middleware populates): e.g. mw(auth.RequireAdmin(handler)).
func RequireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sess, ok := SessionFromContext(r.Context())
		if !ok {
			httpx.Error(w, http.StatusUnauthorized, "missing session")
			return
		}
		if sess.Role != api.Admin {
			httpx.Error(w, http.StatusForbidden, "admin role required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// RequireOwner wraps next so only a session belonging to the instance-owning
// account reaches it; anyone else gets 403. This gates the *server's* powers —
// registering/deleting library roots and triggering scans — as distinct from
// RequireAdmin, which gates powers *within* a household. Like RequireAdmin it
// must be composed inside Middleware: mw(auth.RequireOwner(handler)).
//
// Household admin is still required on top: a viewer profile on the owner's
// account can browse the catalog but not re-shape it.
func RequireOwner(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sess, ok := SessionFromContext(r.Context())
		if !ok {
			httpx.Error(w, http.StatusUnauthorized, "missing session")
			return
		}
		if sess.IsOwner == nil || !*sess.IsOwner {
			httpx.Error(w, http.StatusForbidden, "only the account that owns this server can do that")
			return
		}
		if sess.Role != api.Admin {
			httpx.Error(w, http.StatusForbidden, "admin role required")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// SessionFromContext returns the authenticated session set by requireAuth.
func SessionFromContext(ctx context.Context) (api.Session, bool) {
	sess, ok := ctx.Value(sessionKey).(api.Session)
	return sess, ok
}

// CatalogAccountFromContext returns the account whose libraries this request
// browses — the instance owner's — as resolved by Middleware (ARGY-167). Use it
// for every media lookup; use SessionFromContext().AccountId for household data
// (vaults, devices, transcode-session ownership).
func CatalogAccountFromContext(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(catalogKey).(string)
	return id, ok
}

// IsOwnerSession reports whether sess belongs to the instance-owning account.
func IsOwnerSession(sess api.Session) bool {
	return sess.IsOwner != nil && *sess.IsOwner
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if after, ok := strings.CutPrefix(h, "Bearer "); ok {
		return after
	}
	return ""
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid request body")
		return false
	}
	return true
}

func writeAuthError(w http.ResponseWriter, err error) {
	var emailTaken *EmailTakenError
	switch {
	case errors.As(err, &emailTaken):
		// The account-create conflict carries the existing account (ARGY-163).
		httpx.JSON(w, http.StatusConflict, api.AccountConflictError{Error: err.Error(), Account: emailTaken.Account})
	case errors.Is(err, ErrInvalidCredentials):
		httpx.Error(w, http.StatusUnauthorized, "invalid credentials")
	case errors.Is(err, ErrForbidden):
		httpx.Error(w, http.StatusForbidden, "forbidden")
	case errors.Is(err, ErrNotFound):
		httpx.Error(w, http.StatusNotFound, "not found")
	case errors.Is(err, ErrInvalidInput):
		httpx.Error(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, ErrNameTaken), errors.Is(err, ErrEmailTaken), errors.Is(err, ErrLastAdmin), errors.Is(err, ErrSelfDelete), errors.Is(err, ErrOwnerAccount), errors.Is(err, ErrAccountHasLibraries):
		httpx.Error(w, http.StatusConflict, err.Error())
	case errors.Is(err, ErrPasswordRequired), errors.Is(err, ErrWrongPassword), errors.Is(err, ErrAccountDisabled):
		httpx.Error(w, http.StatusForbidden, err.Error())
	default:
		httpx.Error(w, http.StatusInternalServerError, "internal error")
	}
}
