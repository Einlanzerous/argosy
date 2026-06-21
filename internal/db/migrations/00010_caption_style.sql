-- +goose Up
-- Caption styling (ARGY-43): per-device closed-caption appearance, applied via
-- the player's ::cue styling. Nullable — the client falls back to its defaults
-- (1.0 scale, white text, translucent background) when unset.
ALTER TABLE device_preferences ADD COLUMN caption_scale      double precision;
ALTER TABLE device_preferences ADD COLUMN caption_color      text;
ALTER TABLE device_preferences ADD COLUMN caption_background text;

-- +goose Down
ALTER TABLE device_preferences DROP COLUMN IF EXISTS caption_background;
ALTER TABLE device_preferences DROP COLUMN IF EXISTS caption_color;
ALTER TABLE device_preferences DROP COLUMN IF EXISTS caption_scale;
