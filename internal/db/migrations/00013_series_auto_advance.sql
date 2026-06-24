-- +goose Up
-- Series auto-advance (ARGY-89): a per-device toggle for auto-playing the next
-- episode of a series. Default ON so binge-watching works out of the box; viewers
-- who dislike it opt out without losing the feature.
ALTER TABLE device_preferences ADD COLUMN series_auto_advance boolean NOT NULL DEFAULT true;

-- +goose Down
ALTER TABLE device_preferences DROP COLUMN IF EXISTS series_auto_advance;
