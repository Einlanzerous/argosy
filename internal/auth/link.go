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

// StartLink mints a pending pairing code for a new device to display while it
// polls for approval. Unauthenticated: the code is useless until a signed-in
// user approves the specific code shown on their own screen. The device may
// announce its name/platform so the approver sees what they're blessing
// (ARGY-123); empty values are stored as NULL and defaulted on approval.
func (s *Store) StartLink(ctx context.Context, deviceName, platform string) (api.LinkStartResponse, error) {
	expires := time.Now().Add(linkCodeTTL)
	name := nullIfEmpty(deviceName)
	plat := nullIfEmpty(normalizePlatform(platform))
	// Retry on the (astronomically rare) code collision against an active code.
	for attempt := 0; attempt < 5; attempt++ {
		code, err := generateLinkCode()
		if err != nil {
			return api.LinkStartResponse{}, err
		}
		_, err = s.pool.Exec(ctx,
			`INSERT INTO link_codes (code, expires_at, device_name, platform)
			 VALUES ($1, $2, $3, $4)`, code, expires, name, plat)
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
	var token, deviceName, platform *string
	var expiresAt time.Time
	err := s.pool.QueryRow(ctx,
		`SELECT device_token, expires_at, device_name, platform FROM link_codes WHERE code = $1`, code).
		Scan(&token, &expiresAt, &deviceName, &platform)
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
		// Echo the device-announced identity so an approving UI can show what
		// is about to be linked before blessing the code.
		return api.LinkStatusResponse{Status: api.Pending, DeviceName: deviceName, Platform: platform}, nil
	}
	// Approved: hand the token over once, then consume the code.
	_, _ = s.pool.Exec(ctx, `DELETE FROM link_codes WHERE code = $1`, code)
	return api.LinkStatusResponse{Status: api.Approved, Token: token, DeviceName: deviceName, Platform: platform}, nil
}

// ApproveLink links the device holding `code` to the approving session's
// account and profile: it creates the device and stashes its one-time token on
// the code for the new device to claim on its next poll. The Fleet name is the
// approver's override, else the name the device announced at start, else the
// legacy "Living Room TV" default; likewise platform falls back to androidtv
// for old clients that announce nothing.
func (s *Store) ApproveLink(ctx context.Context, sess api.Session, code, deviceName string) error {
	var existing, announcedName, announcedPlatform *string
	var expiresAt time.Time
	err := s.pool.QueryRow(ctx,
		`SELECT device_token, expires_at, device_name, platform FROM link_codes WHERE code = $1`, code).
		Scan(&existing, &expiresAt, &announcedName, &announcedPlatform)
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
	if name == "" && announcedName != nil {
		name = strings.TrimSpace(*announcedName)
	}
	if name == "" {
		name = "Living Room TV"
	}
	platform := "androidtv"
	if announcedPlatform != nil && *announcedPlatform != "" {
		platform = *announcedPlatform
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO devices (account_id, user_id, name, token_hash, platform)
		 VALUES ($1, $2, $3, $4, $5)`,
		sess.AccountId.String(), sess.UserId.String(), name, hashToken(token), platform); err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `UPDATE link_codes SET device_token = $1 WHERE code = $2`, token, code)
	return err
}

// normalizePlatform maps a device-announced platform onto the known Fleet set;
// anything unrecognized is dropped (approval then defaults to androidtv).
func normalizePlatform(p string) string {
	switch strings.ToLower(strings.TrimSpace(p)) {
	case "android":
		return "android"
	case "ios":
		return "ios"
	case "androidtv":
		return "androidtv"
	case "web":
		return "web"
	default:
		return ""
	}
}

func nullIfEmpty(s string) *string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return &s
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
