-- +goose Up
-- Instance ownership (ARGY-167). Argosy's model was multi-tenant by account —
-- `libraries.account_id` scoped the catalog per account — but a deployment is
-- one household's server. Every provisioned member therefore got an empty
-- tenant and was told to go point Argosy at media folders it doesn't own.
--
-- One account owns the instance: its libraries ARE the server's catalog, and
-- only it may register/delete library roots or trigger scans. `users.role`
-- keeps its existing meaning — admin/viewer *within* a household — so every
-- account still manages its own profiles, devices and Fleet.
ALTER TABLE accounts ADD COLUMN is_owner boolean NOT NULL DEFAULT false;

-- At most one owner. A partial index leaves non-owners unconstrained while
-- making a second claim fail loudly instead of silently forking the catalog.
CREATE UNIQUE INDEX accounts_single_owner ON accounts (is_owner) WHERE is_owner;

-- Backfill: the account that already holds the media owns the instance. Chosen
-- by library count (tie-break oldest) rather than a hardcoded email so this is
-- correct on every existing deployment, not just ours. A fresh install has no
-- accounts yet and matches nothing — CreateAccount claims ownership for the
-- first account instead.
UPDATE accounts SET is_owner = true
WHERE id = (
  SELECT a.id
  FROM accounts a
  LEFT JOIN libraries l ON l.account_id = a.id
  GROUP BY a.id, a.created_at
  ORDER BY count(l.id) DESC, a.created_at ASC
  LIMIT 1
);

-- Every household needs at least one admin, or it can never add a profile —
-- UpdateProfile/DeleteProfile already refuse to remove the last one, but nothing
-- guaranteed there was ever a first. Accounts bootstrapped through the ARGY-159
-- first-login path got a lone *viewer* profile and were stuck. Promote the
-- oldest profile of any admin-less account. Safe now that admin means household
-- admin only; the server's own powers key off is_owner above.
UPDATE users u SET role = 'admin'
WHERE u.role = 'viewer'
  AND NOT EXISTS (
    SELECT 1 FROM users a WHERE a.account_id = u.account_id AND a.role = 'admin'
  )
  AND u.id = (
    SELECT id FROM users x WHERE x.account_id = u.account_id
    ORDER BY x.created_at, x.id LIMIT 1
  );

-- +goose Down
DROP INDEX accounts_single_owner;
ALTER TABLE accounts DROP COLUMN is_owner;
