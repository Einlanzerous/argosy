// Package auth implements account login, per-device token issuance, and the
// bearer middleware that resolves the current (account, user, device, role).
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	openapi_types "github.com/oapi-codegen/runtime/types"
	"golang.org/x/crypto/bcrypt"
)

// Sentinel errors mapped to HTTP statuses by the handlers.
var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrForbidden          = errors.New("forbidden")
	ErrNotFound           = errors.New("not found")
)

// Store is the auth data layer over the connection pool.
type Store struct{ pool *pgxpool.Pool }

// NewStore returns a Store backed by pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// AccountExists reports whether an account with the given username exists.
func (s *Store) AccountExists(ctx context.Context, username string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx, `SELECT exists(SELECT 1 FROM accounts WHERE username = $1)`, username).Scan(&ok)
	return ok, err
}

// CreateAccount creates an account with a bcrypt-hashed password and an initial
// admin profile, returning the account.
func (s *Store) CreateAccount(ctx context.Context, username, password, accountName string) (api.Account, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return api.Account{}, fmt.Errorf("hash password: %w", err)
	}
	var idStr, name string
	if err := s.pool.QueryRow(ctx,
		`INSERT INTO accounts (name, username, password_hash) VALUES ($1, $2, $3) RETURNING id::text, name`,
		accountName, username, string(hash)).Scan(&idStr, &name); err != nil {
		return api.Account{}, fmt.Errorf("insert account: %w", err)
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO users (account_id, name, role) VALUES ($1, $2, 'admin')`,
		idStr, accountName); err != nil {
		return api.Account{}, fmt.Errorf("insert admin profile: %w", err)
	}
	return api.Account{Id: parseUUID(idStr), Name: name}, nil
}

// Login verifies account credentials and returns the account with its profiles.
func (s *Store) Login(ctx context.Context, username, password string) (api.LoginResponse, error) {
	accID, name, err := s.verify(ctx, username, password)
	if err != nil {
		return api.LoginResponse{}, err
	}
	profiles, err := s.profiles(ctx, accID)
	if err != nil {
		return api.LoginResponse{}, err
	}
	return api.LoginResponse{
		Account:  api.Account{Id: parseUUID(accID), Name: name},
		Profiles: profiles,
	}, nil
}

// RegisterDevice re-authenticates and binds a new device to a profile of the
// account, returning the device and a one-time plaintext bearer token.
func (s *Store) RegisterDevice(ctx context.Context, req api.DeviceRegistrationRequest) (api.DeviceRegistrationResponse, error) {
	accID, _, err := s.verify(ctx, req.Username, req.Password)
	if err != nil {
		return api.DeviceRegistrationResponse{}, err
	}
	userID := req.UserId.String()
	var belongs bool
	if err := s.pool.QueryRow(ctx,
		`SELECT exists(SELECT 1 FROM users WHERE id = $1 AND account_id = $2)`, userID, accID).Scan(&belongs); err != nil {
		return api.DeviceRegistrationResponse{}, err
	}
	if !belongs {
		return api.DeviceRegistrationResponse{}, ErrForbidden
	}

	token, err := generateToken()
	if err != nil {
		return api.DeviceRegistrationResponse{}, err
	}
	var platform *string
	if req.Platform != nil && *req.Platform != "" {
		platform = req.Platform
	}
	row := s.pool.QueryRow(ctx,
		`INSERT INTO devices (account_id, user_id, name, token_hash, platform)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id::text, name, platform, user_id::text, last_seen_at, revoked_at, created_at`,
		accID, userID, req.DeviceName, hashToken(token), platform)
	dev, err := scanDevice(row)
	if err != nil {
		return api.DeviceRegistrationResponse{}, err
	}
	return api.DeviceRegistrationResponse{Device: dev, Token: token}, nil
}

// AuthenticateDevice resolves a bearer token to a session, refreshing last-seen.
func (s *Store) AuthenticateDevice(ctx context.Context, token string) (api.Session, error) {
	var accID, devID, role string
	var userID *string
	err := s.pool.QueryRow(ctx,
		`SELECT d.account_id::text, d.id::text, d.user_id::text, coalesce(u.role, 'viewer')
		 FROM devices d LEFT JOIN users u ON u.id = d.user_id
		 WHERE d.token_hash = $1 AND d.revoked_at IS NULL`, hashToken(token)).
		Scan(&accID, &devID, &userID, &role)
	if errors.Is(err, pgx.ErrNoRows) {
		return api.Session{}, ErrInvalidCredentials
	}
	if err != nil {
		return api.Session{}, err
	}
	_, _ = s.pool.Exec(ctx, `UPDATE devices SET last_seen_at = now() WHERE id = $1`, devID)

	sess := api.Session{AccountId: parseUUID(accID), DeviceId: parseUUID(devID), Role: api.Role(role)}
	if userID != nil {
		sess.UserId = parseUUID(*userID)
	}
	return sess, nil
}

// ListDevices returns the account's Fleet. Admins see every device in the
// account; a viewer sees only their own. Each device carries the owning
// profile's display name so the Fleet can show whose device it is.
func (s *Store) ListDevices(ctx context.Context, sess api.Session) ([]api.Device, error) {
	where := `WHERE d.account_id = $1`
	args := []any{sess.AccountId.String()}
	if sess.Role != api.Admin {
		where += ` AND d.user_id = $2`
		args = append(args, sess.UserId.String())
	}
	rows, err := s.pool.Query(ctx,
		`SELECT d.id::text, d.name, d.platform, d.user_id::text, u.name, d.last_seen_at, d.revoked_at, d.created_at
		 FROM devices d LEFT JOIN users u ON u.id = d.user_id `+where+` ORDER BY d.created_at`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.Device{}
	for rows.Next() {
		var id, name string
		var platform, userID, userName *string
		var lastSeen, revokedAt *time.Time
		var createdAt time.Time
		if err := rows.Scan(&id, &name, &platform, &userID, &userName, &lastSeen, &revokedAt, &createdAt); err != nil {
			return nil, err
		}
		dev := api.Device{
			Id: parseUUID(id), Name: name, Platform: platform, UserName: userName,
			LastSeenAt: lastSeen, Revoked: revokedAt != nil, CreatedAt: createdAt,
		}
		if userID != nil {
			u := parseUUID(*userID)
			dev.UserId = &u
		}
		out = append(out, dev)
	}
	return out, rows.Err()
}

// RevokeDevice revokes a device. Admins may revoke any device in their account;
// viewers may revoke only their own.
func (s *Store) RevokeDevice(ctx context.Context, sess api.Session, deviceID openapi_types.UUID) error {
	var devAccount string
	var devUser *string
	err := s.pool.QueryRow(ctx,
		`SELECT account_id::text, user_id::text FROM devices WHERE id = $1`, deviceID.String()).
		Scan(&devAccount, &devUser)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if devAccount != sess.AccountId.String() {
		return ErrNotFound
	}
	if sess.Role != api.Admin && (devUser == nil || *devUser != sess.UserId.String()) {
		return ErrForbidden
	}
	_, err = s.pool.Exec(ctx, `UPDATE devices SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL`, deviceID.String())
	return err
}

// RenameDevice gives a device a friendly label, returning the updated device.
// Admins may rename any device in their account; viewers only their own.
func (s *Store) RenameDevice(ctx context.Context, sess api.Session, deviceID openapi_types.UUID, name string) (api.Device, error) {
	var devAccount string
	var devUser *string
	err := s.pool.QueryRow(ctx,
		`SELECT account_id::text, user_id::text FROM devices WHERE id = $1`, deviceID.String()).
		Scan(&devAccount, &devUser)
	if errors.Is(err, pgx.ErrNoRows) {
		return api.Device{}, ErrNotFound
	}
	if err != nil {
		return api.Device{}, err
	}
	if devAccount != sess.AccountId.String() {
		return api.Device{}, ErrNotFound
	}
	if sess.Role != api.Admin && (devUser == nil || *devUser != sess.UserId.String()) {
		return api.Device{}, ErrForbidden
	}
	row := s.pool.QueryRow(ctx,
		`UPDATE devices SET name = $1 WHERE id = $2
		 RETURNING id::text, name, platform, user_id::text, last_seen_at, revoked_at, created_at`,
		name, deviceID.String())
	return scanDevice(row)
}

// GetDevicePreferences returns a device's playback preferences, or sensible
// defaults (subtitles off) when none have been saved yet.
func (s *Store) GetDevicePreferences(ctx context.Context, deviceID string) (api.DevicePreferences, error) {
	var subLang, audLang, capColor, capBg *string
	var capScale *float64
	var subEnabled bool
	err := s.pool.QueryRow(ctx,
		`SELECT subtitle_language, subtitle_enabled, audio_language,
		        caption_scale, caption_color, caption_background
		 FROM device_preferences WHERE device_id = $1`, deviceID).
		Scan(&subLang, &subEnabled, &audLang, &capScale, &capColor, &capBg)
	if errors.Is(err, pgx.ErrNoRows) {
		return api.DevicePreferences{SubtitleEnabled: false}, nil
	}
	if err != nil {
		return api.DevicePreferences{}, err
	}
	out := api.DevicePreferences{SubtitleLanguage: subLang, SubtitleEnabled: subEnabled, AudioLanguage: audLang, CaptionColor: capColor}
	if capScale != nil {
		f := float32(*capScale)
		out.CaptionScale = &f
	}
	if capBg != nil {
		bg := api.DevicePreferencesCaptionBackground(*capBg)
		out.CaptionBackground = &bg
	}
	return out, nil
}

// SetDevicePreferences upserts a device's playback preferences.
func (s *Store) SetDevicePreferences(ctx context.Context, deviceID string, p api.DevicePreferences) (api.DevicePreferences, error) {
	var capBg *string
	if p.CaptionBackground != nil {
		s := string(*p.CaptionBackground)
		capBg = &s
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO device_preferences
		   (device_id, subtitle_language, subtitle_enabled, audio_language, caption_scale, caption_color, caption_background, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, now())
		 ON CONFLICT (device_id) DO UPDATE SET
		   subtitle_language = EXCLUDED.subtitle_language,
		   subtitle_enabled = EXCLUDED.subtitle_enabled,
		   audio_language = EXCLUDED.audio_language,
		   caption_scale = EXCLUDED.caption_scale,
		   caption_color = EXCLUDED.caption_color,
		   caption_background = EXCLUDED.caption_background,
		   updated_at = now()`,
		deviceID, p.SubtitleLanguage, p.SubtitleEnabled, p.AudioLanguage, p.CaptionScale, p.CaptionColor, capBg); err != nil {
		return api.DevicePreferences{}, err
	}
	return s.GetDevicePreferences(ctx, deviceID)
}

func (s *Store) verify(ctx context.Context, username, password string) (id, name string, err error) {
	var hash string
	err = s.pool.QueryRow(ctx,
		`SELECT id::text, name, coalesce(password_hash, '') FROM accounts WHERE username = $1`, username).
		Scan(&id, &name, &hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", ErrInvalidCredentials
	}
	if err != nil {
		return "", "", err
	}
	if hash == "" || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return "", "", ErrInvalidCredentials
	}
	return id, name, nil
}

func (s *Store) profiles(ctx context.Context, accountID string) ([]api.UserProfile, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id::text, name, role FROM users WHERE account_id = $1 ORDER BY name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []api.UserProfile
	for rows.Next() {
		var idStr, name, role string
		if err := rows.Scan(&idStr, &name, &role); err != nil {
			return nil, err
		}
		out = append(out, api.UserProfile{Id: parseUUID(idStr), Name: name, Role: api.Role(role)})
	}
	return out, rows.Err()
}

// row is satisfied by both pgx.Row and pgx.Rows.
type row interface {
	Scan(dest ...any) error
}

func scanDevice(r row) (api.Device, error) {
	var id, name string
	var platform, userID *string
	var lastSeen, revokedAt *time.Time
	var createdAt time.Time
	if err := r.Scan(&id, &name, &platform, &userID, &lastSeen, &revokedAt, &createdAt); err != nil {
		return api.Device{}, err
	}
	dev := api.Device{
		Id:         parseUUID(id),
		Name:       name,
		Platform:   platform,
		LastSeenAt: lastSeen,
		Revoked:    revokedAt != nil,
		CreatedAt:  createdAt,
	}
	if userID != nil {
		u := parseUUID(*userID)
		dev.UserId = &u
	}
	return dev, nil
}

func generateToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func parseUUID(s string) openapi_types.UUID {
	u, _ := uuid.Parse(s)
	return u
}
