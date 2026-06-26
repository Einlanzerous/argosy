package auth

import (
	"context"
	"crypto/rand"
	"errors"
	"strings"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// Sentinel errors for the TV code-pairing flow (ARGY-112).
var (
	ErrLinkNotFound       = errors.New("link code not found")
	ErrLinkAlreadyClaimed = errors.New("link code already approved")
)

const (
	linkCodeTTL = 5 * time.Minute
	// Unambiguous at a glance on a TV across the room: no 0/O/1/I/L.
	linkCodeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	linkCodeLen      = 6
)

// StartLink mints a pending pairing code for a TV to display while it polls for
// approval. Unauthenticated: the code is useless until a signed-in user approves
// the specific code shown on their own screen.
func (s *Store) StartLink(ctx context.Context) (api.LinkStartResponse, error) {
	expires := time.Now().Add(linkCodeTTL)
	// Retry on the (astronomically rare) code collision against an active code.
	for attempt := 0; attempt < 5; attempt++ {
		code, err := generateLinkCode()
		if err != nil {
			return api.LinkStartResponse{}, err
		}
		_, err = s.pool.Exec(ctx,
			`INSERT INTO link_codes (code, expires_at) VALUES ($1, $2)`, code, expires)
		if err == nil {
			return api.LinkStartResponse{Code: code, ExpiresAt: expires}, nil
		}
		var pgErr *pgconn.PgError
		if !errors.As(err, &pgErr) || pgErr.Code != "23505" { // unique_violation
			return api.LinkStartResponse{}, err
		}
	}
	return api.LinkStartResponse{}, errors.New("could not allocate a link code")
}

// LinkStatus reports whether a code has been approved. Once approved it returns
// the device token exactly once and consumes the row (single use). Expired codes
// are treated as not found (and reaped).
func (s *Store) LinkStatus(ctx context.Context, code string) (api.LinkStatusResponse, error) {
	var token *string
	var expiresAt time.Time
	err := s.pool.QueryRow(ctx,
		`SELECT device_token, expires_at FROM link_codes WHERE code = $1`, code).
		Scan(&token, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return api.LinkStatusResponse{}, ErrLinkNotFound
	}
	if err != nil {
		return api.LinkStatusResponse{}, err
	}
	if time.Now().After(expiresAt) {
		_, _ = s.pool.Exec(ctx, `DELETE FROM link_codes WHERE code = $1`, code)
		return api.LinkStatusResponse{}, ErrLinkNotFound
	}
	if token == nil {
		return api.LinkStatusResponse{Status: api.Pending}, nil
	}
	// Approved: hand the token over once, then consume the code.
	_, _ = s.pool.Exec(ctx, `DELETE FROM link_codes WHERE code = $1`, code)
	return api.LinkStatusResponse{Status: api.Approved, Token: token}, nil
}

// ApproveLink links the TV holding `code` to the approving session's account and
// profile: it creates the device and stashes its one-time token on the code for
// the TV to claim on its next poll.
func (s *Store) ApproveLink(ctx context.Context, sess api.Session, code, deviceName string) error {
	var existing *string
	var expiresAt time.Time
	err := s.pool.QueryRow(ctx,
		`SELECT device_token, expires_at FROM link_codes WHERE code = $1`, code).
		Scan(&existing, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrLinkNotFound
	}
	if err != nil {
		return err
	}
	if time.Now().After(expiresAt) {
		_, _ = s.pool.Exec(ctx, `DELETE FROM link_codes WHERE code = $1`, code)
		return ErrLinkNotFound
	}
	if existing != nil {
		return ErrLinkAlreadyClaimed
	}

	token, err := generateToken()
	if err != nil {
		return err
	}
	name := strings.TrimSpace(deviceName)
	if name == "" {
		name = "Living Room TV"
	}
	platform := "androidtv"
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO devices (account_id, user_id, name, token_hash, platform)
		 VALUES ($1, $2, $3, $4, $5)`,
		sess.AccountId.String(), sess.UserId.String(), name, hashToken(token), platform); err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `UPDATE link_codes SET device_token = $1 WHERE code = $2`, token, code)
	return err
}

func generateLinkCode() (string, error) {
	b := make([]byte, linkCodeLen)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	out := make([]byte, linkCodeLen)
	for i := range b {
		out[i] = linkCodeAlphabet[int(b[i])%len(linkCodeAlphabet)]
	}
	return string(out), nil
}
