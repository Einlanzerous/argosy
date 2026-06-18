-- +goose Up
-- Account-level login credentials (ARGY-12). Kept on accounts; profiles (users)
-- are selected after login.
ALTER TABLE accounts ADD COLUMN username text;
ALTER TABLE accounts ADD COLUMN password_hash text;
CREATE UNIQUE INDEX accounts_username_key ON accounts (username);

-- +goose Down
DROP INDEX IF EXISTS accounts_username_key;
ALTER TABLE accounts DROP COLUMN IF EXISTS password_hash;
ALTER TABLE accounts DROP COLUMN IF EXISTS username;
