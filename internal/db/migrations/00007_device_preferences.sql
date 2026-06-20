-- +goose Up
-- Per-device playback preferences (P4, ARGY-37): a device remembers the viewer's
-- preferred subtitle language + on/off and preferred audio language, applied on
-- playback start. One row per device; cascades when the device is removed.
CREATE TABLE device_preferences (
    device_id         uuid PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    subtitle_language text,
    subtitle_enabled  boolean NOT NULL DEFAULT false,
    audio_language    text,
    updated_at        timestamptz NOT NULL DEFAULT now()
);

-- +goose Down
DROP TABLE IF EXISTS device_preferences;
