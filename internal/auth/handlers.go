package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/google/uuid"
)

type ctxKey int

const sessionKey ctxKey = iota

// RegisterRoutes wires the auth endpoints (the OpenAPI auth surface) onto mux.
func RegisterRoutes(mux *http.ServeMux, store *Store) {
	mux.HandleFunc("POST /api/v1/auth/login", handleLogin(store))
	mux.HandleFunc("POST /api/v1/auth/devices", handleRegisterDevice(store))
	mux.Handle("GET /api/v1/auth/devices", requireAuth(store, handleListDevices(store)))
	mux.Handle("DELETE /api/v1/auth/devices/{deviceId}", requireAuth(store, handleRevokeDevice(store)))
	mux.Handle("PATCH /api/v1/auth/devices/{deviceId}", requireAuth(store, handleRenameDevice(store)))
	mux.Handle("POST /api/v1/auth/devices/switch", requireAuth(store, handleSwitchDeviceProfile(store)))
	mux.Handle("GET /api/v1/auth/me", requireAuth(store, handleMe()))
	// Profile management (ARGY-65): any signed-in profile may list; create/edit/
	// delete are admin-gated.
	mux.Handle("GET /api/v1/auth/profiles", requireAuth(store, handleListProfiles(store)))
	mux.Handle("POST /api/v1/auth/profiles", requireAdmin(store, handleCreateProfile(store)))
	mux.Handle("PATCH /api/v1/auth/profiles/{userId}", requireAdmin(store, handleUpdateProfile(store)))
	mux.Handle("DELETE /api/v1/auth/profiles/{userId}", requireAdmin(store, handleDeleteProfile(store)))
	// TV code-pairing (ARGY-112): start + poll are unauthenticated (a TV with no
	// session yet); approve is the authenticated web user blessing the code.
	mux.HandleFunc("POST /api/v1/auth/link/start", handleStartLink(store))
	mux.HandleFunc("GET /api/v1/auth/link/{code}", handleLinkStatus(store))
	mux.Handle("POST /api/v1/auth/link/{code}/approve", requireAuth(store, handleApproveLink(store)))
	mux.Handle("GET /api/v1/preferences", requireAuth(store, handleGetPreferences(store)))
	mux.Handle("PUT /api/v1/preferences", requireAuth(store, handleSetPreferences(store)))
	mux.Handle("GET /api/v1/user/preferences", requireAuth(store, handleGetUserPreferences(store)))
	mux.Handle("PUT /api/v1/user/preferences", requireAuth(store, handleSetUserPreferences(store)))
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
		resp, err := store.Login(r.Context(), req.Username, req.Password)
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

func handleMe() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		httpx.JSON(w, http.StatusOK, sess)
	}
}

func handleStartLink(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		resp, err := store.StartLink(r.Context())
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
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), sessionKey, sess)))
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

// SessionFromContext returns the authenticated session set by requireAuth.
func SessionFromContext(ctx context.Context) (api.Session, bool) {
	sess, ok := ctx.Value(sessionKey).(api.Session)
	return sess, ok
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
	switch {
	case errors.Is(err, ErrInvalidCredentials):
		httpx.Error(w, http.StatusUnauthorized, "invalid credentials")
	case errors.Is(err, ErrForbidden):
		httpx.Error(w, http.StatusForbidden, "forbidden")
	case errors.Is(err, ErrNotFound):
		httpx.Error(w, http.StatusNotFound, "not found")
	case errors.Is(err, ErrInvalidInput):
		httpx.Error(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, ErrNameTaken), errors.Is(err, ErrLastAdmin), errors.Is(err, ErrSelfDelete):
		httpx.Error(w, http.StatusConflict, err.Error())
	case errors.Is(err, ErrPasswordRequired), errors.Is(err, ErrWrongPassword):
		httpx.Error(w, http.StatusForbidden, err.Error())
	default:
		httpx.Error(w, http.StatusInternalServerError, "internal error")
	}
}
