-- +goose Up
-- ARGY-98: remember which device last reported a playhead for (user, item) so the
-- Continue Watching rail can show a "⇄ <device>" pill when you left off on a
-- different deck in your Fleet. ON DELETE SET NULL: revoking or removing a device
-- only drops the attribution, never the resume position itself.
ALTER TABLE play_state ADD COLUMN device_id uuid REFERENCES devices(id) ON DELETE SET NULL;

-- +goose Down
ALTER TABLE play_state DROP COLUMN IF EXISTS device_id;
