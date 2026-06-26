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
	mux.Handle("GET /api/v1/auth/me", requireAuth(store, handleMe()))
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

func handleMe() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := SessionFromContext(r.Context())
		httpx.JSON(w, http.StatusOK, sess)
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
	default:
		httpx.Error(w, http.StatusInternalServerError, "internal error")
	}
}
