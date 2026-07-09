-- +goose Up
-- PIN-first onboarding (ARGY-123): the new device announces what it is when it
-- mints a code, so the approver sees "Pixel 9 (android)" instead of a bare code
-- and the created Fleet device gets the right name/platform (previously
-- hardcoded to "Living Room TV"/androidtv on approval).
ALTER TABLE link_codes ADD COLUMN device_name text;
ALTER TABLE link_codes ADD COLUMN platform text;

-- +goose Down
ALTER TABLE link_codes DROP COLUMN IF EXISTS platform;
ALTER TABLE link_codes DROP COLUMN IF EXISTS device_name;
