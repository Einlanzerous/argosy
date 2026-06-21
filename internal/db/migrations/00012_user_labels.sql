-- +goose Up
-- User-applied labels (ARGY-73): a profile's own custom tags on a film or series,
-- distinct from the path-derived media_items.tags Stevedore writes automatically.
-- An entry references exactly one of a media_item (film) or a series; the partial
-- unique indexes also prevent the same label twice on one item for one user.
CREATE TABLE user_labels (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    media_item_id uuid REFERENCES media_items(id) ON DELETE CASCADE,
    series_id     uuid REFERENCES series(id) ON DELETE CASCADE,
    label         text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_label_one_ref CHECK ((media_item_id IS NOT NULL) <> (series_id IS NOT NULL))
);
CREATE UNIQUE INDEX idx_user_labels_movie ON user_labels (user_id, media_item_id, label) WHERE media_item_id IS NOT NULL;
CREATE UNIQUE INDEX idx_user_labels_series ON user_labels (user_id, series_id, label) WHERE series_id IS NOT NULL;
CREATE INDEX idx_user_labels_user ON user_labels (user_id, label);

-- +goose Down
DROP TABLE IF EXISTS user_labels;
