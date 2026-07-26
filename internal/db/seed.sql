-- Idempotent dev seed: one household account with two profiles (admin + viewer).
-- Run with `make seed` against the dev stack.
--
-- The account gets a real email + password so it can be signed into through
-- the browser (LoginView uses <input type="email">; an email-less account is
-- unreachable there — ARGY-169). Credentials: demo@argosy.dev / changeme.

INSERT INTO accounts (id, name, email, password_hash)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Demo Household',
    'demo@argosy.dev',
    -- bcrypt("changeme"), cost 10
    '$2a$10$TYUqleSpF3pk8QMuuWnOeuVA7MtbcNvoQPjQ9tX0/bEfj88iCCjUi'
)
ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email, password_hash = EXCLUDED.password_hash
    WHERE accounts.email IS NULL;   -- backfill a pre-ARGY-159 seeded row; never clobber a changed login

INSERT INTO users (account_id, name, role)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'Construct', 'admin'),
    ('00000000-0000-0000-0000-000000000001', 'Guest', 'viewer')
ON CONFLICT (account_id, name) DO NOTHING;
