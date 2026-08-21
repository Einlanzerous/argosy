package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/jackc/pgx/v5"
)

// Account lifecycle beyond create (ARGY-86). Creation belongs to provisioning
// (Purser) and the first-run bootstrap; everything here — list, disable,
// delete, password reset — is the instance owner administering the accounts on
// their server, so the handlers gate on RequireOwner rather than household
// admin.

// ErrOwnerAccount guards every mutating lifecycle operation: disabling or
// deleting the owner's account would brick the server, and resetting its
// password from a mere device session would let a stolen token take the whole
// instance over (the self-serve change-password flow proves the current
// password instead).
var ErrOwnerAccount = errors.New("the instance owner's account can't be modified here")

// ErrAccountHasLibraries refuses deleting an account that still owns library
// rows. Post-ARGY-167 only the (undeletable) owner can create libraries, but
// the 00023 backfill never moved legacy rows — and accounts→libraries→
// media_items cascades on delete, so deleting such an account would silently
// take catalog items (and everyone's watch history on them) with it.
var ErrAccountHasLibraries = errors.New("this account still owns media libraries; move or delete them first")

// email is coalesced: rows born before ARGY-159's cutover may hold NULL.
const accountSummaryCols = `a.id::text, coalesce(a.email, ''), a.name, a.is_owner, a.disabled_at, a.created_at,
	(SELECT count(*) FROM users u WHERE u.account_id = a.id)`

func scanAccountSummary(r row) (api.AccountSummary, error) {
	var idStr, email, name string
	var isOwner bool
	var disabledAt *time.Time
	var createdAt time.Time
	var profileCount int
	if err := r.Scan(&idStr, &email, &name, &isOwner, &disabledAt, &createdAt, &profileCount); err != nil {
		return api.AccountSummary{}, err
	}
	return api.AccountSummary{
		Id: parseUUID(idStr), Email: email, Name: name, IsOwner: isOwner,
		Disabled: disabledAt != nil, CreatedAt: createdAt, ProfileCount: profileCount,
	}, nil
}

// ListAccounts returns every account on the instance, owner first then oldest
// first — the order the household list reads naturally in.
func (s *Store) ListAccounts(ctx context.Context) ([]api.AccountSummary, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+accountSummaryCols+` FROM accounts a ORDER BY a.is_owner DESC, a.created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.AccountSummary{}
	for rows.Next() {
		acc, err := scanAccountSummary(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, acc)
	}
	return out, rows.Err()
}

// lifecycleTarget loads the target account and applies the shared guards:
// it must exist and must not be the instance owner's.
func (s *Store) lifecycleTarget(ctx context.Context, accountID string) (email string, err error) {
	var isOwner bool
	err = s.pool.QueryRow(ctx,
		`SELECT coalesce(email, ''), is_owner FROM accounts WHERE id = $1`, accountID).Scan(&email, &isOwner)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", err
	}
	if isOwner {
		return "", ErrOwnerAccount
	}
	return email, nil
}

// SetAccountDisabled disables or re-enables an account. Disabling keeps every
// row the account owns but stops sign-in (verify) and device authentication
// (AuthenticateDevice) immediately; re-enabling restores both. Idempotent — a
// second disable doesn't move the timestamp.
//
// This is the revoke primitive the provisioning service offboards with
// (ARGY-187) as well as the owner's disable switch, so it takes the audit
// actor rather than a session: there is no session behind an X-Provision-Token
// call. Note what it deliberately does *not* do — revoke the account's device
// rows. AuthenticateDevice already refuses them while the account is disabled,
// and leaving the rows intact is what lets a re-enable restore the Fleet
// instead of making the member re-pair every device (contrast
// ResetAccountPassword, where the credential may be in someone else's hands
// and the pairings really are suspect).
func (s *Store) SetAccountDisabled(ctx context.Context, actor auditEntry, accountID string, disabled bool) (api.AccountSummary, error) {
	email, err := s.lifecycleTarget(ctx, accountID)
	if err != nil {
		return api.AccountSummary{}, err
	}
	set := `disabled_at = NULL`
	if disabled {
		set = `disabled_at = coalesce(disabled_at, now())`
	}
	acc, err := scanAccountSummary(s.pool.QueryRow(ctx,
		`UPDATE accounts a SET `+set+`, updated_at = now() WHERE a.id = $1
		 RETURNING `+accountSummaryCols, accountID))
	if err != nil {
		return api.AccountSummary{}, err
	}
	actor.action, actor.targetType, actor.targetID = "account.disable", "account", accountID
	if !disabled {
		actor.action = "account.enable"
	}
	actor.detail = map[string]any{"email": email}
	s.audit(ctx, actor)
	return acc, nil
}

// DeleteAccount removes an account and everything scoped to it — profiles,
// devices, watch history, vaults, preferences — via the schema's ON DELETE
// CASCADE chain. The owner guard in lifecycleTarget is what makes this safe to
// expose at all.
func (s *Store) DeleteAccount(ctx context.Context, actor auditEntry, accountID string) error {
	email, err := s.lifecycleTarget(ctx, accountID)
	if err != nil {
		return err
	}
	var hasLibraries bool
	if err := s.pool.QueryRow(ctx,
		`SELECT exists(SELECT 1 FROM libraries WHERE account_id = $1)`, accountID).Scan(&hasLibraries); err != nil {
		return err
	}
	if hasLibraries {
		return ErrAccountHasLibraries
	}
	if _, err := s.pool.Exec(ctx, `DELETE FROM accounts WHERE id = $1`, accountID); err != nil {
		return fmt.Errorf("delete account: %w", err)
	}
	actor.action, actor.targetType, actor.targetID = "account.delete", "account", accountID
	actor.detail = map[string]any{"email": email}
	s.audit(ctx, actor)
	return nil
}

// DeprovisionAccountByEmail is DeleteAccount keyed the way the provisioning
// service originally addressed people (ARGY-86 parity with createAccount).
// Superseded by the id-keyed admin routes (ARGY-187) now that Purser records
// the account id at creation, but kept: it is a released endpoint, and an
// operator holding only an email still has a way in.
func (s *Store) DeprovisionAccountByEmail(ctx context.Context, email string) error {
	acc, err := s.AccountByEmail(ctx, email)
	if err != nil {
		return err
	}
	return s.DeleteAccount(ctx, provisionActor(), acc.Id.String())
}

// ResetAccountPassword replaces the account's password with a fresh generated
// one, returned exactly once — the provisioning contract. There is no variant
// that accepts a chosen password: the owner should never know (or pick) a
// member's long-term credential.
//
// Unlike self-serve ChangePassword (which proves the current password, so the
// account's devices are known-good and deliberately stay signed in), an owner
// reset means the credential was lost or leaked — and in the leak case anyone
// holding it may already have paired a device. The reset therefore revokes the
// account's devices too; the member re-pairs with the fresh password.
func (s *Store) ResetAccountPassword(ctx context.Context, sess api.Session, accountID string) (api.PasswordResetResponse, error) {
	email, err := s.lifecycleTarget(ctx, accountID)
	if err != nil {
		return api.PasswordResetResponse{}, err
	}
	password, err := generatePassword()
	if err != nil {
		return api.PasswordResetResponse{}, fmt.Errorf("generate password: %w", err)
	}
	hash, err := hashPassword(password)
	if err != nil {
		return api.PasswordResetResponse{}, err
	}
	if _, err := s.pool.Exec(ctx,
		`UPDATE accounts SET password_hash = $1, updated_at = now() WHERE id = $2`, hash, accountID); err != nil {
		return api.PasswordResetResponse{}, err
	}
	tag, err := s.pool.Exec(ctx,
		`UPDATE devices SET revoked_at = now() WHERE account_id = $1 AND revoked_at IS NULL`, accountID)
	if err != nil {
		return api.PasswordResetResponse{}, err
	}
	e := sessionActor(sess)
	e.action, e.targetType, e.targetID = "account.password_reset", "account", accountID
	e.detail = map[string]any{"email": email, "devicesRevoked": tag.RowsAffected()}
	s.audit(ctx, e)
	return api.PasswordResetResponse{GeneratedPassword: password}, nil
}
