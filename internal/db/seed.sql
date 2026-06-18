-- Idempotent dev seed: one household account with two profiles (admin + viewer).
-- Run with `make seed` against the dev stack.

INSERT INTO accounts (id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Demo Household')
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (account_id, name, role)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'Construct', 'admin'),
    ('00000000-0000-0000-0000-000000000001', 'Guest', 'viewer')
ON CONFLICT (account_id, name) DO NOTHING;
