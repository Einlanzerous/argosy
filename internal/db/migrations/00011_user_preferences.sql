-- +goose Up
-- Per-user (per-profile) preferences, distinct from the per-device prefs in P4.
-- First field: home layout density — "discovery" shows all rows (vault + genre
-- rows included), "focused" trims to the personal/actionable rows.
CREATE TABLE user_preferences (
    user_id     uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    home_layout text NOT NULL DEFAULT 'discovery' CHECK (home_layout IN ('focused', 'discovery')),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- +goose Down
DROP TABLE IF EXISTS user_preferences;
