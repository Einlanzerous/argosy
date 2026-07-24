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
	"strings"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	openapi_types "github.com/oapi-codegen/runtime/types"
	"golang.org/x/crypto/bcrypt"
)

// Sentinel errors mapped to HTTP statuses by the handlers.
var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrForbidden          = errors.New("forbidden")
	ErrNotFound           = errors.New("not found")
	// Profile-management conflicts (ARGY-65), surfaced as 400/409.
	ErrInvalidInput = errors.New("invalid input")
	ErrNameTaken    = errors.New("a profile with that name already exists")
	ErrLastAdmin    = errors.New("the account must keep at least one admin")
	ErrSelfDelete   = errors.New("you can't delete the profile you're signed in as")
	// Device profile-switch (ARGY-85): escalating into an admin profile needs the
	// account password. Both surface as 403 (never 401 — a bad switch password
	// must not look like an expired token and sign the device out).
	ErrPasswordRequired = errors.New("the account password is required to switch to an admin profile")
	ErrWrongPassword    = errors.New("incorrect account password")
)

// minPasswordLen is the floor for a new account password (ARGY-156). Mirrored
// by the PasswordChangeRequest minLength in the OpenAPI spec.
const minPasswordLen = 8

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
	var installID *string
	if req.InstallId != nil && *req.InstallId != "" {
		installID = req.InstallId
	}
	// Upsert on (account_id, install_id): a re-pair from the same physical device
	// reuses (and un-revokes) its row with a fresh token instead of piling up a
	// new one. A nil install_id has no partial-index entry, so it falls through to
	// a plain insert — the legacy insert-every-time behavior.
	row := s.pool.QueryRow(ctx,
		`INSERT INTO devices (account_id, user_id, name, token_hash, platform, install_id)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 ON CONFLICT (account_id, install_id) WHERE install_id IS NOT NULL
		 DO UPDATE SET
		   user_id = EXCLUDED.user_id,
		   name = EXCLUDED.name,
		   token_hash = EXCLUDED.token_hash,
		   platform = EXCLUDED.platform,
		   revoked_at = NULL
		 RETURNING id::text, name, platform, user_id::text, last_seen_at, revoked_at, created_at`,
		accID, userID, req.DeviceName, hashToken(token), platform, installID)
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

// SwitchDeviceProfile re-points the calling device to another profile in the same
// account without re-pairing — the device token is unchanged, only its user_id
// binding moves. Switching into an admin profile requires the account password so
// a viewer device can't silently assume admin. Returns the refreshed session.
func (s *Store) SwitchDeviceProfile(ctx context.Context, sess api.Session, targetUserID, password string) (api.Session, error) {
	accountID := sess.AccountId.String()
	var role string
	err := s.pool.QueryRow(ctx,
		`SELECT role FROM users WHERE id = $1 AND account_id = $2`, targetUserID, accountID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return api.Session{}, ErrNotFound
	}
	if err != nil {
		return api.Session{}, err
	}
	// Escalation guard: assuming an admin profile requires the account password.
	if role == "admin" {
		if password == "" {
			return api.Session{}, ErrPasswordRequired
		}
		ok, err := s.checkAccountPassword(ctx, accountID, password)
		if err != nil {
			return api.Session{}, err
		}
		if !ok {
			return api.Session{}, ErrWrongPassword
		}
	}
	// Re-point the current (non-revoked) device. Scope to the account as defense
	// in depth even though the device id comes from the authenticated session.
	tag, err := s.pool.Exec(ctx,
		`UPDATE devices SET user_id = $1 WHERE id = $2 AND account_id = $3 AND revoked_at IS NULL`,
		targetUserID, sess.DeviceId.String(), accountID)
	if err != nil {
		return api.Session{}, err
	}
	if tag.RowsAffected() == 0 {
		return api.Session{}, ErrNotFound
	}
	return api.Session{
		AccountId: sess.AccountId,
		DeviceId:  sess.DeviceId,
		UserId:    parseUUID(targetUserID),
		Role:      api.Role(role),
	}, nil
}

// ChangePassword verifies the current account password and replaces it with a
// new bcrypt hash (ARGY-156). Device tokens live in devices.token_hash and are
// independent of the password, so existing devices deliberately stay signed in.
func (s *Store) ChangePassword(ctx context.Context, accountID, currentPassword, newPassword string) error {
	if len(newPassword) < minPasswordLen {
		return fmt.Errorf("%w: the new password must be at least %d characters", ErrInvalidInput, minPasswordLen)
	}
	ok, err := s.checkAccountPassword(ctx, accountID, currentPassword)
	if err != nil {
		return err
	}
	if !ok {
		return ErrWrongPassword
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}
	_, err = s.pool.Exec(ctx,
		`UPDATE accounts SET password_hash = $1, updated_at = now() WHERE id = $2`, string(hash), accountID)
	return err
}

// checkAccountPassword reports whether password matches the account's bcrypt hash.
func (s *Store) checkAccountPassword(ctx context.Context, accountID, password string) (bool, error) {
	var hash string
	err := s.pool.QueryRow(ctx,
		`SELECT coalesce(password_hash, '') FROM accounts WHERE id = $1`, accountID).Scan(&hash)
	if err != nil {
		return false, err
	}
	if hash == "" {
		return false, nil
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil, nil
}

// GetDevicePreferences returns a device's playback preferences, or sensible
// defaults (subtitles off) when none have been saved yet.
func (s *Store) GetDevicePreferences(ctx context.Context, deviceID string) (api.DevicePreferences, error) {
	var subLang, audLang, capColor, capBg, capPos *string
	var capScale *float64
	var subEnabled, autoAdvance bool
	err := s.pool.QueryRow(ctx,
		`SELECT subtitle_language, subtitle_enabled, audio_language,
		        caption_scale, caption_color, caption_background, caption_position, series_auto_advance
		 FROM device_preferences WHERE device_id = $1`, deviceID).
		Scan(&subLang, &subEnabled, &audLang, &capScale, &capColor, &capBg, &capPos, &autoAdvance)
	if errors.Is(err, pgx.ErrNoRows) {
		// No row yet: subtitles default off, series auto-advance default on.
		on := true
		return api.DevicePreferences{SubtitleEnabled: false, SeriesAutoAdvance: &on}, nil
	}
	if err != nil {
		return api.DevicePreferences{}, err
	}
	out := api.DevicePreferences{SubtitleLanguage: subLang, SubtitleEnabled: subEnabled, AudioLanguage: audLang, CaptionColor: capColor, SeriesAutoAdvance: &autoAdvance}
	if capScale != nil {
		f := float32(*capScale)
		out.CaptionScale = &f
	}
	if capBg != nil {
		bg := api.DevicePreferencesCaptionBackground(*capBg)
		out.CaptionBackground = &bg
	}
	if capPos != nil {
		pos := api.DevicePreferencesCaptionPosition(*capPos)
		out.CaptionPosition = &pos
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
	var capPos *string
	if p.CaptionPosition != nil {
		s := string(*p.CaptionPosition)
		capPos = &s
	}
	// Auto-advance defaults on; a client that omits the field shouldn't flip it off.
	autoAdvance := true
	if p.SeriesAutoAdvance != nil {
		autoAdvance = *p.SeriesAutoAdvance
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO device_preferences
		   (device_id, subtitle_language, subtitle_enabled, audio_language, caption_scale, caption_color, caption_background, caption_position, series_auto_advance, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
		 ON CONFLICT (device_id) DO UPDATE SET
		   subtitle_language = EXCLUDED.subtitle_language,
		   subtitle_enabled = EXCLUDED.subtitle_enabled,
		   audio_language = EXCLUDED.audio_language,
		   caption_scale = EXCLUDED.caption_scale,
		   caption_color = EXCLUDED.caption_color,
		   caption_background = EXCLUDED.caption_background,
		   caption_position = EXCLUDED.caption_position,
		   series_auto_advance = EXCLUDED.series_auto_advance,
		   updated_at = now()`,
		deviceID, p.SubtitleLanguage, p.SubtitleEnabled, p.AudioLanguage, p.CaptionScale, p.CaptionColor, capBg, capPos, autoAdvance); err != nil {
		return api.DevicePreferences{}, err
	}
	return s.GetDevicePreferences(ctx, deviceID)
}

// GetUserPreferences returns the profile's account-wide preferences, defaulting
// to the discovery home layout when none have been saved.
func (s *Store) GetUserPreferences(ctx context.Context, userID string) (api.UserPreferences, error) {
	var layout string
	err := s.pool.QueryRow(ctx,
		`SELECT home_layout FROM user_preferences WHERE user_id = $1`, userID).Scan(&layout)
	if errors.Is(err, pgx.ErrNoRows) {
		return api.UserPreferences{HomeLayout: api.Discovery}, nil
	}
	if err != nil {
		return api.UserPreferences{}, err
	}
	return api.UserPreferences{HomeLayout: api.UserPreferencesHomeLayout(layout)}, nil
}

// SetUserPreferences upserts the profile's preferences. Unknown layouts fall back
// to discovery (the DB CHECK would otherwise reject them).
func (s *Store) SetUserPreferences(ctx context.Context, userID string, p api.UserPreferences) (api.UserPreferences, error) {
	layout := string(p.HomeLayout)
	if layout != "focused" && layout != "discovery" {
		layout = "discovery"
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO user_preferences (user_id, home_layout, updated_at) VALUES ($1, $2, now())
		 ON CONFLICT (user_id) DO UPDATE SET home_layout = EXCLUDED.home_layout, updated_at = now()`,
		userID, layout); err != nil {
		return api.UserPreferences{}, err
	}
	return s.GetUserPreferences(ctx, userID)
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

// ListProfiles returns every profile in the account with its active (non-revoked)
// device count, so the management UI can warn before deleting a profile in use.
func (s *Store) ListProfiles(ctx context.Context, accountID string) ([]api.ProfileSummary, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT u.id::text, u.name, u.role,
		        (SELECT count(*) FROM devices d WHERE d.user_id = u.id AND d.revoked_at IS NULL)
		 FROM users u WHERE u.account_id = $1 ORDER BY u.name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.ProfileSummary{}
	for rows.Next() {
		var idStr, name, role string
		var count int
		if err := rows.Scan(&idStr, &name, &role, &count); err != nil {
			return nil, err
		}
		out = append(out, api.ProfileSummary{Id: parseUUID(idStr), Name: name, Role: api.Role(role), DeviceCount: count})
	}
	return out, rows.Err()
}

// CreateProfile adds a profile to the account. Names are unique per account.
func (s *Store) CreateProfile(ctx context.Context, accountID, name string, role api.Role) (api.ProfileSummary, error) {
	name = strings.TrimSpace(name)
	if name == "" || !validRole(role) {
		return api.ProfileSummary{}, ErrInvalidInput
	}
	var idStr string
	err := s.pool.QueryRow(ctx,
		`INSERT INTO users (account_id, name, role) VALUES ($1, $2, $3) RETURNING id::text`,
		accountID, name, string(role)).Scan(&idStr)
	if isUniqueViolation(err) {
		return api.ProfileSummary{}, ErrNameTaken
	}
	if err != nil {
		return api.ProfileSummary{}, err
	}
	return api.ProfileSummary{Id: parseUUID(idStr), Name: name, Role: role, DeviceCount: 0}, nil
}

// UpdateProfile renames a profile and/or changes its role; nil fields are left
// as-is. Demoting the only admin is refused so an account can't lock itself out.
func (s *Store) UpdateProfile(ctx context.Context, accountID, userID string, name *string, role *api.Role) (api.ProfileSummary, error) {
	var curRole string
	err := s.pool.QueryRow(ctx,
		`SELECT role FROM users WHERE id = $1 AND account_id = $2`, userID, accountID).Scan(&curRole)
	if errors.Is(err, pgx.ErrNoRows) {
		return api.ProfileSummary{}, ErrNotFound
	}
	if err != nil {
		return api.ProfileSummary{}, err
	}

	var nameArg *string
	if name != nil {
		trimmed := strings.TrimSpace(*name)
		if trimmed == "" {
			return api.ProfileSummary{}, ErrInvalidInput
		}
		nameArg = &trimmed
	}
	var roleArg *string
	if role != nil {
		if !validRole(*role) {
			return api.ProfileSummary{}, ErrInvalidInput
		}
		// Demoting an admin: make sure another admin remains.
		if *role == api.Viewer && curRole == "admin" {
			ok, err := s.hasOtherAdmin(ctx, accountID, userID)
			if err != nil {
				return api.ProfileSummary{}, err
			}
			if !ok {
				return api.ProfileSummary{}, ErrLastAdmin
			}
		}
		r := string(*role)
		roleArg = &r
	}

	var idStr, newName, newRole string
	var count int
	err = s.pool.QueryRow(ctx,
		`UPDATE users SET name = COALESCE($1, name), role = COALESCE($2, role), updated_at = now()
		 WHERE id = $3 AND account_id = $4
		 RETURNING id::text, name, role,
		   (SELECT count(*) FROM devices d WHERE d.user_id = users.id AND d.revoked_at IS NULL)`,
		nameArg, roleArg, userID, accountID).Scan(&idStr, &newName, &newRole, &count)
	if isUniqueViolation(err) {
		return api.ProfileSummary{}, ErrNameTaken
	}
	if err != nil {
		return api.ProfileSummary{}, err
	}
	return api.ProfileSummary{Id: parseUUID(idStr), Name: newName, Role: api.Role(newRole), DeviceCount: count}, nil
}

// DeleteProfile removes a profile from the account. Devices bound to it are
// unbound by the FK (ON DELETE SET NULL) and drop to viewer access. The account
// must keep an admin, and you can't delete the profile you're signed in as.
func (s *Store) DeleteProfile(ctx context.Context, sess api.Session, userID string) error {
	if userID == sess.UserId.String() {
		return ErrSelfDelete
	}
	accountID := sess.AccountId.String()
	var role string
	err := s.pool.QueryRow(ctx,
		`SELECT role FROM users WHERE id = $1 AND account_id = $2`, userID, accountID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if role == "admin" {
		ok, err := s.hasOtherAdmin(ctx, accountID, userID)
		if err != nil {
			return err
		}
		if !ok {
			return ErrLastAdmin
		}
	}
	_, err = s.pool.Exec(ctx, `DELETE FROM users WHERE id = $1 AND account_id = $2`, userID, accountID)
	return err
}

// hasOtherAdmin reports whether the account has an admin other than excludeID.
func (s *Store) hasOtherAdmin(ctx context.Context, accountID, excludeID string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx,
		`SELECT exists(SELECT 1 FROM users WHERE account_id = $1 AND role = 'admin' AND id <> $2)`,
		accountID, excludeID).Scan(&ok)
	return ok, err
}

func validRole(r api.Role) bool { return r == api.Admin || r == api.Viewer }

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
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
