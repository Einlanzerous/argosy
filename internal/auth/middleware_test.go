package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Einlanzerous/argosy/internal/api"
)

func TestRequireAdmin(t *testing.T) {
	newReq := func(sess *api.Session) *http.Request {
		r := httptest.NewRequest(http.MethodPost, "/x", nil)
		if sess != nil {
			r = r.WithContext(context.WithValue(r.Context(), sessionKey, *sess))
		}
		return r
	}

	cases := []struct {
		name       string
		sess       *api.Session
		wantStatus int
		wantCalled bool
	}{
		{"admin passes", &api.Session{Role: api.Admin}, http.StatusOK, true},
		{"viewer forbidden", &api.Session{Role: api.Viewer}, http.StatusForbidden, false},
		{"no session unauthorized", nil, http.StatusUnauthorized, false},
	}
	for _, c := range cases {
		called := false
		h := RequireAdmin(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			called = true
			w.WriteHeader(http.StatusOK)
		}))
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, newReq(c.sess))
		if rr.Code != c.wantStatus || called != c.wantCalled {
			t.Errorf("%s: status=%d called=%v, want status=%d called=%v", c.name, rr.Code, called, c.wantStatus, c.wantCalled)
		}
	}
}
