-- +goose Up
-- ARGY-325 (SATL-31): scoped credentials for other services, kept apart from
-- `devices` on purpose. A device token means "a signed-in household device" and
-- carries an account; a service token carries neither, and no route that takes
-- a device token accepts it. Additive: users.role, the Role enum and every
-- existing table are untouched.
--
-- Only the sha256 of the token is stored; the plaintext is shown once by
-- `argosy service-token mint`. consumer_label is NOT unique so a rotation can
-- hold two live tokens for one consumer (mint the new one, then revoke the old).
-- A revoked token keeps its row: the audit trail and `list` still name it.
CREATE TABLE service_tokens (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    consumer_label text NOT NULL,
    scope          text NOT NULL,
    token_hash     text NOT NULL UNIQUE,
    created_at     timestamptz NOT NULL DEFAULT now(),
    last_used_at   timestamptz,
    revoked_at     timestamptz
);
CREATE INDEX service_tokens_consumer_label ON service_tokens (consumer_label);

-- +goose Down
DROP TABLE service_tokens;
