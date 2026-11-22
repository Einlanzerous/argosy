package server

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/ballast"
	"github.com/Einlanzerous/argosy/internal/beacon"
	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/presence"
	"github.com/Einlanzerous/argosy/internal/stevedore"
	"github.com/Einlanzerous/argosy/internal/stow"
	"github.com/Einlanzerous/argosy/internal/subtitle"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/jackc/pgx/v5/pgxpool"
	openapi_types "github.com/oapi-codegen/runtime/types"
)

// ARGY-325 (SATL-31). A service token is accepted on exactly one route. These
// tests enumerate the LIVE mux through the routeRecorder and compare what a
// service token gets against what a stranger gets, route by route, so a future
// route cannot quietly start honouring it (or be added without anyone deciding
// what credential it takes).

type routeClass string

const (
	classPublic       routeClass = "public"         // answers anonymously
	classDevice       routeClass = "device"         // bearer device session
	classOwnerOrAdmin routeClass = "owner_or_admin" // device session + role gate
	classProvision    routeClass = "provision"      // X-Provision-Token
	classInlineToken  routeClass = "inline_token"   // ?token= device token, checked in the handler
	classSummary      routeClass = "summary"        // the one route a service token opens
)

// routeClasses pins how every registered route authenticates. Adding a route
// means adding a row here, which is the moment someone decides its credential.
var routeClasses = map[string]routeClass{
	"GET /healthz":                                          classPublic,
	"GET /api/v1/ping":                                      classPublic,
	"/":                                                     classPublic, // SPA shell and its JSON 404 for unknown /api/ paths
	"GET /artwork/":                                         classPublic,
	"POST /api/v1/auth/login":                               classPublic,
	"POST /api/v1/auth/devices":                             classPublic, // credentials are in the body
	"POST /api/v1/auth/link/start":                          classPublic,
	"GET /api/v1/auth/link/{code}":                          classPublic,
	"GET /api/v1/sessions/summary":                          classSummary,
	"GET /api/v1/beacon":                                    classInlineToken,
	"GET /api/v1/items/{itemId}/stream":                     classInlineToken,
	"GET /api/v1/items/{itemId}/subtitles/{trackId}":        classInlineToken,
	"GET /api/v1/stow/{jobId}/file":                         classInlineToken,
	"POST /api/v1/admin/accounts":                           classProvision,
	"GET /api/v1/admin/accounts":                            classProvision,
	"DELETE /api/v1/admin/accounts":                         classProvision,
	"PATCH /api/v1/admin/accounts/{accountId}":              classProvision,
	"DELETE /api/v1/admin/accounts/{accountId}":             classProvision,
	"POST /api/v1/auth/profiles":                            classOwnerOrAdmin,
	"PATCH /api/v1/auth/profiles/{userId}":                  classOwnerOrAdmin,
	"DELETE /api/v1/auth/profiles/{userId}":                 classOwnerOrAdmin,
	"GET /api/v1/auth/accounts":                             classOwnerOrAdmin,
	"PATCH /api/v1/auth/accounts/{accountId}":               classOwnerOrAdmin,
	"DELETE /api/v1/auth/accounts/{accountId}":              classOwnerOrAdmin,
	"POST /api/v1/auth/accounts/{accountId}/password-reset": classOwnerOrAdmin,
	"POST /api/v1/libraries":                                classOwnerOrAdmin,
	"DELETE /api/v1/libraries/{libraryId}":                  classOwnerOrAdmin,
	"POST /api/v1/scan":                                     classOwnerOrAdmin,
	"GET /api/v1/scan/status":                               classOwnerOrAdmin,

	"GET /api/v1/auth/devices":                        classDevice,
	"DELETE /api/v1/auth/devices/{deviceId}":          classDevice,
	"PATCH /api/v1/auth/devices/{deviceId}":           classDevice,
	"POST /api/v1/auth/devices/switch":                classDevice,
	"GET /api/v1/auth/me":                             classDevice,
	"POST /api/v1/auth/password":                      classDevice,
	"GET /api/v1/auth/profiles":                       classDevice,
	"POST /api/v1/auth/link/{code}/approve":           classDevice,
	"GET /api/v1/preferences":                         classDevice,
	"PUT /api/v1/preferences":                         classDevice,
	"GET /api/v1/user/preferences":                    classDevice,
	"PUT /api/v1/user/preferences":                    classDevice,
	"GET /api/v1/libraries":                           classDevice,
	"GET /api/v1/libraries/{libraryId}/movies":        classDevice,
	"GET /api/v1/libraries/{libraryId}/series":        classDevice,
	"GET /api/v1/series/{seriesId}":                   classDevice,
	"GET /api/v1/items/{itemId}":                      classDevice,
	"GET /api/v1/continue":                            classDevice,
	"GET /api/v1/ondeck":                              classDevice,
	"GET /api/v1/recent":                              classDevice,
	"GET /api/v1/search":                              classDevice,
	"GET /api/v1/facets":                              classDevice,
	"GET /api/v1/vaults":                              classDevice,
	"POST /api/v1/vaults":                             classDevice,
	"GET /api/v1/vaults/{vaultId}":                    classDevice,
	"PATCH /api/v1/vaults/{vaultId}":                  classDevice,
	"DELETE /api/v1/vaults/{vaultId}":                 classDevice,
	"POST /api/v1/vaults/{vaultId}/items":             classDevice,
	"DELETE /api/v1/vaults/{vaultId}/items/{entryId}": classDevice,
	"PUT /api/v1/vaults/{vaultId}/order":              classDevice,
	"GET /api/v1/sessions":                            classDevice,
	"GET /api/v1/items/{itemId}/playback":             classDevice,
	"GET /api/v1/items/{itemId}/next-episode":         classDevice,
	"GET /api/v1/items/{itemId}/progress":             classDevice,
	"PUT /api/v1/items/{itemId}/progress":             classDevice,
	"POST /api/v1/items/{itemId}/playback-events":     classDevice,
	"POST /api/v1/items/{itemId}/watched":             classDevice,
	"POST /api/v1/series/{seriesId}/watched":          classDevice,
	"POST /api/v1/seasons/{seasonId}/watched":         classDevice,
	"GET /api/v1/items/{itemId}/subtitles":            classDevice,
	"POST /api/v1/items/{itemId}/transcode":           classDevice,
	"GET /api/v1/transcode/sessions":                  classDevice,
	"DELETE /api/v1/transcode/{sessionId}":            classDevice,
	"GET /api/v1/transcode/capabilities":              classDevice,
	"GET /api/v1/transcode/cache":                     classDevice,
	"GET /api/v1/transcode/{sessionId}/{file}":        classDevice,
	"POST /api/v1/items/{itemId}/stow":                classDevice,
	"GET /api/v1/stow":                                classDevice,
	"GET /api/v1/stow/{jobId}":                        classDevice,
	"DELETE /api/v1/stow/{jobId}":                     classDevice,
}

// unclassified returns the recorded patterns that have no row in table, sorted.
// It is the completeness check, factored out so a fixture can prove it bites.
func unclassified(recorded []string, table map[string]routeClass) []string {
	var out []string
	for _, p := range recorded {
		if _, ok := table[p]; !ok {
			out = append(out, p)
		}
	}
	sort.Strings(out)
	return out
}

func discardLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

type fullServer struct {
	handler http.Handler
	rec     *httpx.RouteRecorder
	store   *auth.Store
	pool    *pgxpool.Pool
	pres    *presence.Registry
	cfg     config.Config
}

// newFullServer builds the server with every dependency non-nil, so every
// conditional route (sessions, beacon, subtitles, transcode, cache, stow, scan,
// provisioning, artwork) is registered. pres == nil builds it without presence.
func newFullServer(t *testing.T, withPresence bool) *fullServer {
	t.Helper()
	dsn := testdb.DSN(t)
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)

	logger := discardLogger()
	cfg := config.Config{
		ProvisionToken: "test-provision-" + strconv.FormatInt(time.Now().UnixNano(), 36),
		ArtworkDir:     t.TempDir(),
	}
	tc := transcode.NewManager(nil, t.TempDir(), time.Minute, 2, logger)
	sweeper := ballast.NewSweeper(t.TempDir(), 1<<20, time.Minute, tc, logger, time.Hour)
	subs := subtitle.NewService(nil, t.TempDir(), []string{"en"}, logger)
	stowMgr := stow.New(pool, nil, t.TempDir(), transcode.EncoderSoftware, 1, time.Hour, logger)
	sched := stevedore.NewScheduler(pool, logger, t.TempDir(), nil, time.Hour)
	hub := beacon.NewHub(pool, logger)
	var pres *presence.Registry
	if withPresence {
		pres = presence.NewRegistry(0)
	}

	srv, rec, err := build(cfg, logger, pool, sched, tc, transcode.Capabilities{}, transcode.EncoderSoftware, sweeper, subs, pres, hub, stowMgr)
	if err != nil {
		t.Fatalf("build: %v", err)
	}
	return &fullServer{handler: srv.Handler, rec: rec, store: auth.NewStore(pool), pool: pool, pres: pres, cfg: cfg}
}

func (s *fullServer) mint(t *testing.T) (token, id string) {
	t.Helper()
	label := "t" + strconv.FormatInt(time.Now().UnixNano(), 36)
	tok, row, err := s.store.MintServiceToken(context.Background(), label, auth.ScopeSessionsSummary, "test")
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	return tok, row.ID
}

func (s *fullServer) do(method, target string, hdr map[string]string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, target, nil)
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rr := httptest.NewRecorder()
	s.handler.ServeHTTP(rr, req)
	return rr
}

const placeholderID = "00000000-0000-4000-8000-000000000001"

// concretePath turns a registered pattern into a request path the mux routes to
// that same pattern.
func concretePath(pattern string) (method, path string) {
	method = http.MethodGet
	path = pattern
	if m, p, ok := strings.Cut(pattern, " "); ok {
		method, path = m, p
	}
	for {
		i := strings.Index(path, "{")
		if i < 0 {
			break
		}
		j := strings.Index(path[i:], "}")
		path = path[:i] + placeholderID + path[i+j+1:]
	}
	if path == "/artwork/" {
		path = "/artwork/none.jpg"
	}
	return method, path
}

// Criteria 0 and 1: every live route has a class, and a service token gets
// exactly what a stranger gets everywhere but the summary.
func TestServiceTokenRouteClasses(t *testing.T) {
	s := newFullServer(t, true)
	token, _ := s.mint(t)
	recorded := s.rec.Patterns()

	if missing := unclassified(recorded, routeClasses); len(missing) > 0 {
		t.Fatalf("routes with no row in routeClasses (decide their credential and add them): %v", missing)
	}
	for p := range routeClasses {
		if !slices.Contains(recorded, p) {
			t.Errorf("routeClasses has a row for %q, which is not registered with every dependency set (stale row?)", p)
		}
	}
	if len(recorded) != len(routeClasses) {
		t.Errorf("recorded %d patterns, table has %d rows", len(recorded), len(routeClasses))
	}

	for _, pattern := range recorded {
		class := routeClasses[pattern]
		method, path := concretePath(pattern)

		// Prove the request below is dispatched to the pattern under test and not
		// to a sibling or the SPA fallback.
		probe := httptest.NewRequest(method, path, nil)
		if _, got := s.rec.Mux.Handler(probe); got != pattern {
			t.Errorf("%s: request %s %s routes to %q", pattern, method, path, got)
			continue
		}

		anon := s.do(method, path, nil)
		// The token is offered every way a credential can be offered here:
		// bearer, ?token= (the inline-auth routes) and the provisioning header.
		withToken := s.do(method, path+queryJoin(path)+"token="+url.QueryEscape(token), map[string]string{
			"Authorization":     "Bearer " + token,
			"X-Provision-Token": token,
		})

		switch class {
		case classSummary:
			if anon.Code != http.StatusUnauthorized {
				t.Errorf("%s: anonymous got %d, want 401", pattern, anon.Code)
			}
			if withToken.Code != http.StatusOK {
				t.Errorf("%s: service token got %d, want 200", pattern, withToken.Code)
			}
		case classPublic:
			if withToken.Code != anon.Code || withToken.Header().Get("Content-Type") != anon.Header().Get("Content-Type") {
				t.Errorf("%s (public): service token got %d %q, anonymous got %d %q — the token must change nothing",
					pattern, withToken.Code, withToken.Header().Get("Content-Type"), anon.Code, anon.Header().Get("Content-Type"))
			}
		default:
			// No handler body runs for a refused credential: each of these answers
			// 401 from its own auth step, before any handler logic.
			if anon.Code != http.StatusUnauthorized || withToken.Code != http.StatusUnauthorized {
				t.Errorf("%s (%s): anonymous %d, service token %d, want 401 for both", pattern, class, anon.Code, withToken.Code)
			}
		}
	}
}

func queryJoin(path string) string {
	if strings.Contains(path, "?") {
		return "&"
	}
	return "?"
}

// Criterion 1: the completeness check fails on a route nobody classified. The
// fixture registers a synthetic route through a recorder exactly as server.New
// would and asserts the check names it.
func TestRouteClassCompletenessCatchesAnUnclassifiedRoute(t *testing.T) {
	rec := httpx.NewRouteRecorder()
	rec.HandleFunc("GET /api/v1/ping", handlePing)
	if got := unclassified(rec.Patterns(), routeClasses); len(got) != 0 {
		t.Fatalf("a classified route was reported unclassified: %v", got)
	}
	rec.HandleFunc("GET /api/v1/synthetic-new-route", func(http.ResponseWriter, *http.Request) {})
	rec.Handle("DELETE /api/v1/another/{id}", http.NotFoundHandler())
	got := unclassified(rec.Patterns(), routeClasses)
	want := []string{"DELETE /api/v1/another/{id}", "GET /api/v1/synthetic-new-route"}
	if !slices.Equal(got, want) {
		t.Fatalf("unclassified = %v, want %v", got, want)
	}
}

type summaryBody struct {
	WatchingNow int       `json:"watchingNow"`
	AsOf        time.Time `json:"asOf"`
}

// Criterion 2: exactly {watchingNow, asOf}; playing sessions summed across
// accounts; a literal 0 on an empty registry.
func TestSessionsSummaryCountsAcrossAccountsAndLeaksNothing(t *testing.T) {
	s := newFullServer(t, true)
	token, _ := s.mint(t)
	hdr := map[string]string{"Authorization": "Bearer " + token}

	rr := s.do("GET", "/api/v1/sessions/summary", hdr)
	if rr.Code != http.StatusOK {
		t.Fatalf("empty registry: status %d", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), `"watchingNow":0`) {
		t.Fatalf("empty registry must report a literal 0, got %s", rr.Body.String())
	}

	// Two accounts, plus a paused session that must not count.
	s.pres.Heartbeat(presence.Session{AccountID: "acct-a", UserID: "u1", DeviceID: "d1", ItemID: "i1", PositionSeconds: 42})
	s.pres.Heartbeat(presence.Session{AccountID: "acct-a", UserID: "u2", DeviceID: "d2", ItemID: "i2"})
	s.pres.Heartbeat(presence.Session{AccountID: "acct-b", UserID: "u3", DeviceID: "d3", ItemID: "i3"})
	s.pres.Heartbeat(presence.Session{AccountID: "acct-b", UserID: "u4", DeviceID: "d4", ItemID: "i4", State: "paused"})

	rr = s.do("GET", "/api/v1/sessions/summary", hdr)
	if rr.Code != http.StatusOK {
		t.Fatalf("status %d", rr.Code)
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal(rr.Body.Bytes(), &keys); err != nil {
		t.Fatal(err)
	}
	got := make([]string, 0, len(keys))
	for k := range keys {
		got = append(got, k)
	}
	sort.Strings(got)
	if !slices.Equal(got, []string{"asOf", "watchingNow"}) {
		t.Fatalf("response keys = %v, want exactly [asOf watchingNow]", got)
	}
	var body summaryBody
	if err := json.Unmarshal(rr.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.WatchingNow != 3 {
		t.Errorf("watchingNow = %d, want 3 (two accounts, paused excluded)", body.WatchingNow)
	}
	if time.Since(body.AsOf) > time.Minute || body.AsOf.IsZero() {
		t.Errorf("asOf = %v, want about now", body.AsOf)
	}
	// None of the seeded identifiers may appear anywhere in the body.
	for _, leak := range []string{"acct-", "u1", "d1", "i1", "position", "encoder", "method", "deviceId", "userId", "itemId"} {
		if strings.Contains(rr.Body.String(), leak) {
			t.Errorf("body contains %q: %s", leak, rr.Body.String())
		}
	}
}

// Criterion 3: without a presence registry the route does not exist, exactly as
// /api/v1/sessions does not. It must never answer 200 {watchingNow: 0}.
func TestSessionsSummaryAbsentWithoutPresence(t *testing.T) {
	s := newFullServer(t, false)
	token, _ := s.mint(t)
	for _, p := range s.rec.Patterns() {
		if strings.HasSuffix(p, "/api/v1/sessions/summary") || strings.HasSuffix(p, "/api/v1/sessions") {
			t.Errorf("%q is registered with no presence registry", p)
		}
	}
	rr := s.do("GET", "/api/v1/sessions/summary", map[string]string{"Authorization": "Bearer " + token})
	if rr.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rr.Code)
	}
	if strings.Contains(rr.Body.String(), "watchingNow") {
		t.Fatalf("body must not carry a count: %s", rr.Body.String())
	}
}

// Criterion 4: mint, call, revoke, call again with no restart; unknown tokens,
// device tokens (admin and viewer) and the provision token are refused.
func TestSessionsSummaryCredentialClasses(t *testing.T) {
	s := newFullServer(t, true)
	ctx := context.Background()
	call := func(tok string) int {
		return s.do("GET", "/api/v1/sessions/summary", map[string]string{"Authorization": "Bearer " + tok}).Code
	}

	token, id := s.mint(t)
	if got := call(token); got != http.StatusOK {
		t.Fatalf("live token: %d, want 200", got)
	}
	if _, err := s.store.RevokeServiceTokens(ctx, id, "", "test"); err != nil {
		t.Fatal(err)
	}
	if got := call(token); got != http.StatusUnauthorized {
		t.Fatalf("revoked token: %d, want 401 on the next request, no restart", got)
	}
	if got := call("ags_not-a-real-token"); got != http.StatusUnauthorized {
		t.Fatalf("unknown token: %d, want 401", got)
	}
	if got := call(s.cfg.ProvisionToken); got != http.StatusUnauthorized {
		t.Fatalf("provision token as bearer: %d, want 401", got)
	}
	if got := s.do("GET", "/api/v1/sessions/summary", map[string]string{"X-Provision-Token": s.cfg.ProvisionToken}).Code; got != http.StatusUnauthorized {
		t.Fatalf("provision token in its own header: %d, want 401", got)
	}

	// Real device tokens: an admin profile and a viewer profile.
	email := "svc-" + strconv.FormatInt(time.Now().UnixNano(), 36) + "@example.test"
	password := "pw-" + strconv.FormatInt(time.Now().UnixNano(), 36)
	acct, err := s.store.CreateAccount(ctx, email, password, "Svc Household")
	if err != nil {
		t.Fatal(err)
	}
	login, err := s.store.Login(ctx, email, password)
	if err != nil {
		t.Fatal(err)
	}
	admin := login.Profiles[0]
	viewer, err := s.store.CreateProfile(ctx, acct.Id.String(), "viewer", api.Viewer)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []struct {
		ID   openapi_types.UUID
		Role api.Role
	}{{admin.Id, admin.Role}, {viewer.Id, viewer.Role}} {
		uid := p.ID
		reg, err := s.store.RegisterDevice(ctx, api.DeviceRegistrationRequest{Email: email, Password: password, UserId: &uid, DeviceName: "svc-test"})
		if err != nil {
			t.Fatalf("register %s device: %v", p.Role, err)
		}
		// The device token is genuine: it works on a device route...
		if got := s.do("GET", "/api/v1/auth/me", map[string]string{"Authorization": "Bearer " + reg.Token}).Code; got != http.StatusOK {
			t.Fatalf("%s device token on /auth/me: %d, want 200", p.Role, got)
		}
		// ...and is refused on the summary route.
		if got := call(reg.Token); got != http.StatusUnauthorized {
			t.Errorf("%s device token on summary: %d, want 401", p.Role, got)
		}
	}
}
