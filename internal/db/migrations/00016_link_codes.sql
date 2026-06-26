-- +goose Up
-- TV code-pairing (ARGY-112): a TV mints a short code, an authenticated user
-- approves it from the web, and the TV claims a device token — so nobody types
-- credentials on a remote. Rows are short-lived and single-use: device_token is
-- set on approval, handed to the TV on its next poll, and the row deleted.
CREATE TABLE link_codes (
    code         text PRIMARY KEY,
    device_token text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL
);

-- +goose Down
DROP TABLE IF EXISTS link_codes;
