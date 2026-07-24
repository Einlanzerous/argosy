-- +goose Up
-- Account identity is email + password; profiles are the usernames (ARGY-159).
-- The credential column was born as free-form `username` (00002); rename it to
-- what it actually holds now and make uniqueness case-insensitive. No format
-- CHECK on purpose: pre-cutover rows may still hold legacy non-email values,
-- and they must keep logging in until the ops backfill completes.
ALTER TABLE accounts RENAME COLUMN username TO email;
DROP INDEX accounts_username_key;
CREATE UNIQUE INDEX accounts_email_key ON accounts (lower(email));

-- +goose Down
DROP INDEX accounts_email_key;
ALTER TABLE accounts RENAME COLUMN email TO username;
CREATE UNIQUE INDEX accounts_username_key ON accounts (username);
