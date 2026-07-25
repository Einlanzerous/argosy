package auth

import (
	"context"
	"errors"
	"sync"

	"github.com/jackc/pgx/v5"
)

// Instance ownership (ARGY-167).
//
// Argosy stores libraries per account (`libraries.account_id`), but a deployment
// is one household's server: the media belongs to the machine, not to whoever
// happens to sign in. One account owns the instance, and its libraries are the
// catalog every client browses. Household data — profiles, devices, vaults,
// watch progress — stays scoped to the caller's own account, so `users.role`
// keeps meaning admin/viewer *within* a household.

// ownerCache memoizes the owner's account id. Ownership is claimed once (by the
// 00023 migration on an existing deployment, or by the first CreateAccount on a
// fresh one) and effectively never changes, so a positive answer is cached for
// the process lifetime. A negative answer is deliberately NOT cached: a fresh
// install has no owner until its first account exists, and that must take
// effect without waiting for a restart.
type ownerCache struct {
	mu sync.RWMutex
	id string
}

func (c *ownerCache) get() (string, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.id, c.id != ""
}

func (c *ownerCache) set(id string) {
	c.mu.Lock()
	c.id = id
	c.mu.Unlock()
}

// OwnerAccountID returns the account id that owns this instance. ok is false
// when no account has claimed ownership yet (a fresh install with no accounts).
func (s *Store) OwnerAccountID(ctx context.Context) (string, bool, error) {
	if id, ok := s.owner.get(); ok {
		return id, true, nil
	}
	var id string
	// Hits the accounts_single_owner partial index.
	err := s.pool.QueryRow(ctx, `SELECT id::text FROM accounts WHERE is_owner LIMIT 1`).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	s.owner.set(id)
	return id, true, nil
}

// CatalogAccountID returns the account whose libraries the caller should browse:
// the instance owner's. It falls back to callerAccountID when no owner is
// designated, which preserves pre-ARGY-167 behavior on a fresh install rather
// than serving an empty catalog.
func (s *Store) CatalogAccountID(ctx context.Context, callerAccountID string) (string, error) {
	id, ok, err := s.OwnerAccountID(ctx)
	if err != nil {
		return "", err
	}
	if !ok {
		return callerAccountID, nil
	}
	return id, nil
}

// claimOwnershipIfUnowned makes accountID the instance owner when no account has
// claimed ownership. This is what makes a self-hosted install work out of the
// box: whoever creates the first account owns the server. It is a no-op on an
// instance that already has an owner, so Purser-provisioned members (ARGY-132)
// never take the catalog over.
//
// The guard is a single conditional UPDATE, so two concurrent creations cannot
// both win; accounts_single_owner is the backstop if they somehow raced.
func (s *Store) claimOwnershipIfUnowned(ctx context.Context, accountID string) error {
	tag, err := s.pool.Exec(ctx,
		`UPDATE accounts SET is_owner = true
		 WHERE id = $1 AND NOT EXISTS (SELECT 1 FROM accounts WHERE is_owner)`, accountID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() > 0 {
		s.owner.set(accountID)
	}
	return nil
}
