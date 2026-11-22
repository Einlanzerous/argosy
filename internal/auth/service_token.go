package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"sync"
	"time"

	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Service tokens (ARGY-325, SATL-31): a credential for another service that can
// read one number and nothing else. They live in their own table and are
// accepted by their own middleware on exactly one route. Everything else that
// authenticates (Middleware, the inline ?token= handlers, the provisioning
// token) reads `devices` or a static secret and therefore refuses a service
// token exactly as it refuses a stranger's — that equality is what the
// route-class test in internal/server pins.

// ScopeSessionsSummary lets the holder read GET /api/v1/sessions/summary.
const ScopeSessionsSummary = "sessions:summary"

// serviceScopes is the closed set of scopes a token may be minted with.
var serviceScopes = map[string]bool{ScopeSessionsSummary: true}

// ErrUnknownScope is returned by MintServiceToken for a scope not in the set.
var ErrUnknownScope = errors.New("unknown service-token scope")

// ErrInvalidLabel is returned for a consumer label outside labelPattern.
var ErrInvalidLabel = errors.New("invalid consumer label")

// labelPattern keeps a label safe to put in a log line and an audit row.
var labelPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,39}$`)

// ErrServiceTokenNotFound is returned by revoke when nothing live matched.
var ErrServiceTokenNotFound = errors.New("no live service token matched")

const (
	// tokenPrefix makes a leaked token greppable; it carries no authority.
	tokenPrefix = "ags_"
	// lastUsedEvery is the floor between last_used_at stamps for one token.
	lastUsedEvery = time.Minute
	// refusalWindow is the dedupe window for refused-presentation audit rows.
	refusalWindow = time.Hour
	// hashPrefixLen is how much of the sha256 an audit row records: enough to
	// tell two presentations apart, not enough to be looked up as a credential.
	hashPrefixLen = 12
	// maxRefusalKeys bounds the in-memory dedupe set against a scanner sending
	// endless distinct tokens.
	maxRefusalKeys = 4096

	actorCLI          = "cli"
	actorServiceToken = "service_token"
)

// ServiceToken is a token row as `list` shows it. It has no hash field: a
// listing can't leak what it never loads.
type ServiceToken struct {
	ID            string
	ConsumerLabel string
	Scope         string
	CreatedAt     time.Time
	LastUsedAt    *time.Time
	RevokedAt     *time.Time
}

// MintServiceToken creates a token for label with scope, returning the
// plaintext, which is never stored and never recoverable. osUser names the
// operator running the CLI for the audit row.
func (s *Store) MintServiceToken(ctx context.Context, label, scope, osUser string) (plaintext string, tok ServiceToken, err error) {
	if !labelPattern.MatchString(label) {
		return "", ServiceToken{}, ErrInvalidLabel
	}
	if !serviceScopes[scope] {
		return "", ServiceToken{}, ErrUnknownScope
	}
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", ServiceToken{}, err
	}
	plaintext = tokenPrefix + base64.RawURLEncoding.EncodeToString(raw[:])

	// Detached from the caller's context like every audited action: the token
	// row and its audit row commit together or not at all, and a cancelled
	// context must not leave a live token with no trail.
	ctx = context.WithoutCancel(ctx)
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx,
			`INSERT INTO service_tokens (consumer_label, scope, token_hash) VALUES ($1, $2, $3)
			 RETURNING id::text, created_at`,
			label, scope, hashToken(plaintext)).Scan(&tok.ID, &tok.CreatedAt); err != nil {
			return err
		}
		tok.ConsumerLabel, tok.Scope = label, scope
		return auditTx(ctx, tx, auditEntry{
			actorType: actorCLI, action: "service_token.mint",
			targetType: "service_token", targetID: tok.ID,
			detail: map[string]any{"label": label, "scope": scope, "osUser": osUser},
		})
	})
	if err != nil {
		return "", ServiceToken{}, err
	}
	return plaintext, tok, nil
}

// RevokeServiceTokens sets revoked_at on live tokens, keeping the rows. Exactly
// one of id and label is set; a label revokes every live token carrying it.
// Returns the ids revoked, or ErrServiceTokenNotFound if none were live.
func (s *Store) RevokeServiceTokens(ctx context.Context, id, label, osUser string) ([]string, error) {
	if (id == "") == (label == "") {
		return nil, fmt.Errorf("%w: give exactly one of id and label", ErrInvalidInput)
	}
	if id != "" {
		if _, err := uuid.Parse(id); err != nil {
			return nil, fmt.Errorf("%w: id is not a uuid", ErrInvalidInput)
		}
	}
	ctx = context.WithoutCancel(ctx)
	var ids []string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`UPDATE service_tokens SET revoked_at = now()
			 WHERE revoked_at IS NULL AND (id = nullif($1, '')::uuid OR consumer_label = nullif($2, ''))
			 RETURNING id::text, consumer_label`, id, label)
		if err != nil {
			return err
		}
		type hit struct{ id, label string }
		var hits []hit
		for rows.Next() {
			var h hit
			if err := rows.Scan(&h.id, &h.label); err != nil {
				return err
			}
			hits = append(hits, h)
		}
		if err := rows.Err(); err != nil {
			return err
		}
		for _, h := range hits {
			ids = append(ids, h.id)
			if err := auditTx(ctx, tx, auditEntry{
				actorType: actorCLI, action: "service_token.revoke",
				targetType: "service_token", targetID: h.id,
				detail: map[string]any{"label": h.label, "osUser": osUser},
			}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		return nil, ErrServiceTokenNotFound
	}
	return ids, nil
}

// ListServiceTokens returns every token row, newest first, without hashes.
func (s *Store) ListServiceTokens(ctx context.Context) ([]ServiceToken, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id::text, consumer_label, scope, created_at, last_used_at, revoked_at
		 FROM service_tokens ORDER BY created_at DESC, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ServiceToken
	for rows.Next() {
		var t ServiceToken
		if err := rows.Scan(&t.ID, &t.ConsumerLabel, &t.Scope, &t.CreatedAt, &t.LastUsedAt, &t.RevokedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *Store) inTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// auditTx is audit's transactional sibling: the CLI mutations must not commit
// without their row, so a failure here is returned rather than logged.
func auditTx(ctx context.Context, tx pgx.Tx, e auditEntry) error {
	detailJSON, err := marshalDetail(e.detail)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx,
		`INSERT INTO audit_log (actor_type, actor_account_id, actor_user_id, action, target_type, target_id, detail)
		 VALUES ($1, nullif($2, '')::uuid, nullif($3, '')::uuid, $4, $5, nullif($6, '')::uuid, $7)`,
		e.actorType, e.actorAccountID, e.actorUserID, e.action, e.targetType, e.targetID, detailJSON)
	return err
}

// errServiceTokenRefused is internal: any reason a presented token is not
// accepted. Callers answer 401 for all of them identically.
var errServiceTokenRefused = errors.New("service token refused")

// authenticateServiceToken resolves a presented token to a live row with the
// required scope. It reads only service_tokens. A refusal (unknown, revoked or
// wrong scope) is audited by the caller; a database error is returned as-is.
func (s *Store) authenticateServiceToken(ctx context.Context, plaintext, scope string) (ServiceToken, error) {
	hash := hashToken(plaintext)
	var t ServiceToken
	err := s.pool.QueryRow(ctx,
		`SELECT id::text, consumer_label, scope, created_at, last_used_at, revoked_at
		 FROM service_tokens WHERE token_hash = $1`, hash).
		Scan(&t.ID, &t.ConsumerLabel, &t.Scope, &t.CreatedAt, &t.LastUsedAt, &t.RevokedAt)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		s.auditRefusal(ctx, hash, nil, "unknown")
		return ServiceToken{}, errServiceTokenRefused
	case err != nil:
		return ServiceToken{}, err
	case t.RevokedAt != nil:
		s.auditRefusal(ctx, hash, &t, "revoked")
		return ServiceToken{}, errServiceTokenRefused
	case t.Scope != scope:
		s.auditRefusal(ctx, hash, &t, "wrong_scope")
		return ServiceToken{}, errServiceTokenRefused
	}
	// At most one write a minute per token, decided by the database so two
	// replicas (or a restart) can't double it. Best-effort: a failed stamp must
	// not fail a request that authenticated.
	if _, err := s.pool.Exec(ctx,
		`UPDATE service_tokens SET last_used_at = now()
		 WHERE id = $1 AND (last_used_at IS NULL OR last_used_at < now() - make_interval(secs => $2))`,
		t.ID, lastUsedEvery.Seconds()); err != nil {
		slog.Warn("service token last_used_at stamp failed", "label", t.ConsumerLabel, "err", err)
	}
	return t, nil
}

// refusalLimiter keeps one audit row per hash prefix per hour (ruling 7) from
// costing a database round trip per request. The database check in
// auditRefusal is what survives a restart; this only sheds load.
type refusalLimiter struct {
	mu   sync.Mutex
	seen map[string]time.Time
}

// allow reports whether prefix has not been admitted within refusalWindow, and
// admits it. When the set is full of live entries it refuses rather than grow:
// a scanner flooding distinct tokens loses audit rows, never memory.
func (l *refusalLimiter) allow(prefix string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.seen == nil {
		l.seen = make(map[string]time.Time)
	}
	if at, ok := l.seen[prefix]; ok && now.Sub(at) < refusalWindow {
		return false
	}
	if len(l.seen) >= maxRefusalKeys {
		for k, at := range l.seen {
			if now.Sub(at) >= refusalWindow {
				delete(l.seen, k)
			}
		}
		if len(l.seen) >= maxRefusalKeys {
			return false
		}
	}
	l.seen[prefix] = now
	return true
}

// auditRefusal records a refused presentation: the hash prefix, the token's
// label and id if it exists, and why — never the plaintext. One row per hash
// prefix per hour.
func (s *Store) auditRefusal(ctx context.Context, hash string, known *ServiceToken, reason string) {
	prefix := hash[:hashPrefixLen]
	if !s.refusals.allow(prefix, time.Now()) {
		return
	}
	ctx = context.WithoutCancel(ctx)
	detail := map[string]any{"hashPrefix": prefix, "reason": reason}
	target := ""
	if known != nil {
		detail["label"] = known.ConsumerLabel
		target = known.ID
	}
	detailJSON, err := marshalDetail(detail)
	if err != nil {
		return
	}
	_, err = s.pool.Exec(ctx,
		`INSERT INTO audit_log (actor_type, action, target_type, target_id, detail)
		 SELECT $1, 'service_token.refused', 'service_token', nullif($2, '')::uuid, $3
		 WHERE NOT EXISTS (
		   SELECT 1 FROM audit_log
		   WHERE action = 'service_token.refused' AND detail->>'hashPrefix' = $4
		     AND occurred_at > now() - make_interval(secs => $5))`,
		actorServiceToken, target, detailJSON, prefix, refusalWindow.Seconds())
	if err != nil {
		slog.Warn("audit write failed", "action", "service_token.refused", "err", err)
	}
}

// ServiceTokenMiddleware admits a request only if it carries a live service
// token holding scope. The token comes from the Authorization bearer header and
// nowhere else, and is looked up in service_tokens alone: a device token or the
// provisioning token is simply an unknown service token here and gets 401.
// Every refusal answers the same 401 body, so a caller learns nothing about
// whether a token exists or was revoked. A database error is 503, never a pass.
func ServiceTokenMiddleware(store *Store, scope string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token := bearerToken(r)
			if token == "" {
				httpx.Error(w, http.StatusUnauthorized, "missing bearer token")
				return
			}
			t, err := store.authenticateServiceToken(r.Context(), token, scope)
			switch {
			case errors.Is(err, errServiceTokenRefused):
				httpx.Error(w, http.StatusUnauthorized, "invalid or revoked token")
				return
			case err != nil:
				slog.Error("service token lookup failed", "err", err)
				httpx.Error(w, http.StatusServiceUnavailable, "unavailable")
				return
			}
			// The request log names the consumer, never the token.
			if tr := TraceFromContext(r.Context()); tr != nil {
				tr.SetIdentity("", "", "svc:"+t.ConsumerLabel)
			}
			next.ServeHTTP(w, r)
		})
	}
}
