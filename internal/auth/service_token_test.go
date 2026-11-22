package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
)

func uniqueLabel() string { return "t" + strconv.FormatInt(time.Now().UnixNano(), 36) }

func auditRows(t *testing.T, s *Store, action, label string) []map[string]any {
	t.Helper()
	rows, err := s.pool.Query(context.Background(),
		`SELECT actor_type, detail FROM audit_log WHERE action = $1 AND detail->>'label' = $2 ORDER BY id`, action, label)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var out []map[string]any
	for rows.Next() {
		var actor string
		var raw []byte
		if err := rows.Scan(&actor, &raw); err != nil {
			t.Fatal(err)
		}
		d := map[string]any{}
		if err := json.Unmarshal(raw, &d); err != nil {
			t.Fatal(err)
		}
		d["_actor"] = actor
		out = append(out, d)
	}
	return out
}

// Criterion 5: only the sha256 is stored, revoke keeps the row, list carries no
// hash, and the audit rows survive a cancelled context.
func TestServiceTokenStorageRevokeListAndAudit(t *testing.T) {
	store, _ := testStore(t)
	label := uniqueLabel()

	// A cancelled context stands in for a client that hung up mid-request: the
	// mutation and its audit row must still land (CLAUDE.md: audit outlives it).
	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	plain, tok, err := store.MintServiceToken(cancelled, label, ScopeSessionsSummary, "alice")
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	if !strings.HasPrefix(plain, "ags_") {
		t.Errorf("token %q lacks the ags_ prefix", plain[:min(4, len(plain))])
	}

	var stored string
	if err := store.pool.QueryRow(context.Background(), `SELECT token_hash FROM service_tokens WHERE id = $1`, tok.ID).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored != hashToken(plain) || stored == plain {
		t.Fatal("token_hash must be the sha256 of the plaintext, not the plaintext")
	}
	// The plaintext is nowhere in the audit trail.
	var leaked int
	if err := store.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM audit_log WHERE detail::text LIKE '%' || $1 || '%'`, plain).Scan(&leaked); err != nil || leaked != 0 {
		t.Fatalf("plaintext found in audit_log (n=%d, err=%v)", leaked, err)
	}

	mint := auditRows(t, store, "service_token.mint", label)
	if len(mint) != 1 || mint[0]["_actor"] != "cli" || mint[0]["osUser"] != "alice" || mint[0]["scope"] != ScopeSessionsSummary {
		t.Fatalf("mint audit = %v", mint)
	}

	if _, _, err := store.MintServiceToken(context.Background(), label, "nope", "alice"); !errors.Is(err, ErrUnknownScope) {
		t.Errorf("unknown scope: %v, want ErrUnknownScope", err)
	}
	if _, _, err := store.MintServiceToken(context.Background(), "Bad Label!", ScopeSessionsSummary, "alice"); !errors.Is(err, ErrInvalidLabel) {
		t.Errorf("bad label: %v, want ErrInvalidLabel", err)
	}
	// Rotation: a second live token for the same label is allowed.
	_, second, err := store.MintServiceToken(context.Background(), label, ScopeSessionsSummary, "alice")
	if err != nil {
		t.Fatalf("second mint for a live label: %v", err)
	}

	// Revoke by label takes every live one and keeps the rows.
	ids, err := store.RevokeServiceTokens(cancelled, "", label, "alice")
	if err != nil || len(ids) != 2 {
		t.Fatalf("revoke by label: ids=%v err=%v", ids, err)
	}
	if got := auditRows(t, store, "service_token.revoke", label); len(got) != 2 {
		t.Fatalf("revoke audit rows = %d, want 2", len(got))
	}
	if _, err := store.RevokeServiceTokens(context.Background(), second.ID, "", "alice"); !errors.Is(err, ErrServiceTokenNotFound) {
		t.Errorf("revoking an already-revoked token: %v, want ErrServiceTokenNotFound", err)
	}
	if _, err := store.RevokeServiceTokens(context.Background(), "", "", "alice"); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("revoke with neither id nor label: %v", err)
	}

	toks, err := store.ListServiceTokens(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	found := 0
	for _, x := range toks {
		if x.ConsumerLabel == label {
			found++
			if x.RevokedAt == nil {
				t.Errorf("token %s has no revoked_at after revoke", x.ID)
			}
		}
	}
	if found != 2 {
		t.Errorf("revoked rows kept = %d, want 2", found)
	}
}

func bearerReq(token string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/x", nil)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	return r
}

// Criterion 5: last_used_at at most once a minute; refusals audited once per
// hash prefix per hour with no plaintext; scope mismatch and revoked are 401.
func TestServiceTokenMiddlewareStampsAndAuditsRefusals(t *testing.T) {
	store, ctx := testStore(t)
	label := uniqueLabel()
	plain, tok, err := store.MintServiceToken(ctx, label, ScopeSessionsSummary, "alice")
	if err != nil {
		t.Fatal(err)
	}
	h := ServiceTokenMiddleware(store, ScopeSessionsSummary)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	serve := func(token string) int {
		rr := httptest.NewRecorder()
		h.ServeHTTP(rr, bearerReq(token))
		return rr.Code
	}
	lastUsed := func() time.Time {
		var at *time.Time
		if err := store.pool.QueryRow(ctx, `SELECT last_used_at FROM service_tokens WHERE id = $1`, tok.ID).Scan(&at); err != nil || at == nil {
			t.Fatalf("last_used_at: %v %v", at, err)
		}
		return *at
	}

	if got := serve(plain); got != http.StatusNoContent {
		t.Fatalf("live token: %d", got)
	}
	first := lastUsed()
	for range 3 {
		serve(plain)
	}
	if !lastUsed().Equal(first) {
		t.Error("last_used_at was rewritten inside the one-minute floor")
	}
	// Age the stamp past the floor: the next use stamps again.
	if _, err := store.pool.Exec(ctx, `UPDATE service_tokens SET last_used_at = now() - interval '2 minutes' WHERE id = $1`, tok.ID); err != nil {
		t.Fatal(err)
	}
	serve(plain)
	if time.Since(lastUsed()) > time.Minute {
		t.Error("last_used_at was not stamped after the floor passed")
	}

	if got := serve(""); got != http.StatusUnauthorized {
		t.Errorf("no token: %d", got)
	}

	// Unknown token, presented many times: one audit row, no plaintext.
	stranger := "ags_" + uniqueLabel() + "-stranger"
	for range 5 {
		if got := serve(stranger); got != http.StatusUnauthorized {
			t.Fatalf("unknown token: %d", got)
		}
	}
	prefix := hashToken(stranger)[:hashPrefixLen]
	refusals := func(prefix string) int {
		var n int
		if err := store.pool.QueryRow(ctx,
			`SELECT count(*) FROM audit_log WHERE action = 'service_token.refused' AND detail->>'hashPrefix' = $1`, prefix).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	if n := refusals(prefix); n != 1 {
		t.Fatalf("unknown token wrote %d refusal rows, want 1 per hash prefix per hour", n)
	}
	// A restart forgets the in-memory limiter; the database still dedupes.
	store.refusals = refusalLimiter{}
	serve(stranger)
	if n := refusals(prefix); n != 1 {
		t.Fatalf("after a limiter reset: %d rows, want still 1", n)
	}
	// An hour later it is recorded again.
	if _, err := store.pool.Exec(ctx,
		`UPDATE audit_log SET occurred_at = now() - interval '61 minutes' WHERE action = 'service_token.refused' AND detail->>'hashPrefix' = $1`, prefix); err != nil {
		t.Fatal(err)
	}
	store.refusals = refusalLimiter{}
	serve(stranger)
	if n := refusals(prefix); n != 2 {
		t.Fatalf("after the window: %d rows, want 2", n)
	}
	var leaked int
	if err := store.pool.QueryRow(ctx, `SELECT count(*) FROM audit_log WHERE detail::text LIKE '%' || $1 || '%'`, stranger).Scan(&leaked); err != nil || leaked != 0 {
		t.Fatalf("refused plaintext found in audit_log (n=%d err=%v)", leaked, err)
	}

	// Revoked: 401, and the row names the token's label.
	if _, err := store.RevokeServiceTokens(ctx, tok.ID, "", "alice"); err != nil {
		t.Fatal(err)
	}
	if got := serve(plain); got != http.StatusUnauthorized {
		t.Fatalf("revoked token: %d", got)
	}
	var reason string
	if err := store.pool.QueryRow(ctx,
		`SELECT detail->>'reason' FROM audit_log WHERE action = 'service_token.refused' AND detail->>'label' = $1`, label).Scan(&reason); err != nil || reason != "revoked" {
		t.Fatalf("revoked refusal row: reason=%q err=%v", reason, err)
	}

	// A token whose scope the route does not require is refused too.
	other := ServiceTokenMiddleware(store, "other:scope")(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) }))
	plain2, _, _ := store.MintServiceToken(ctx, label, ScopeSessionsSummary, "alice")
	rr := httptest.NewRecorder()
	other.ServeHTTP(rr, bearerReq(plain2))
	if rr.Code != http.StatusUnauthorized {
		t.Errorf("wrong scope: %d, want 401", rr.Code)
	}
}

func TestRefusalLimiterIsBounded(t *testing.T) {
	var l refusalLimiter
	now := time.Now()
	admitted := 0
	for i := range maxRefusalKeys + 100 {
		if l.allow(strconv.Itoa(i), now) {
			admitted++
		}
	}
	if admitted != maxRefusalKeys || len(l.seen) != maxRefusalKeys {
		t.Fatalf("admitted %d, tracked %d, want both capped at %d", admitted, len(l.seen), maxRefusalKeys)
	}
	if !l.allow("fresh", now.Add(2*refusalWindow)) {
		t.Error("expired entries should be reclaimed to make room")
	}
}
