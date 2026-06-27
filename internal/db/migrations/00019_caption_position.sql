-- +goose Up
-- ARGY-60: persist the caption vertical-position preset (bottom | raised | higher)
-- per device, alongside the existing caption size/colour/background prefs. NULL
-- means "unset" → clients fall back to the raised default.
ALTER TABLE device_preferences ADD COLUMN caption_position text;

-- +goose Down
ALTER TABLE device_preferences DROP COLUMN IF EXISTS caption_position;
