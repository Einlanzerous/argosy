-- +goose Up
-- Free-form tags on media_items and series. This replaces the old top-level
-- "anime" category: anime (and similar) are now tags, not a kind of their own,
-- so a standalone film and a series can both be tagged 'anime' without anime
-- having to be its own bucket. Top-level kinds stay {movie, episode} on
-- media_items (a "film" is a standalone movie); the two browse pieces are
-- series and movies, with tags as a cross-cutting label.
ALTER TABLE media_items ADD COLUMN tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE series ADD COLUMN tags text[] NOT NULL DEFAULT '{}';
CREATE INDEX idx_media_items_tags ON media_items USING gin (tags);
CREATE INDEX idx_series_tags ON series USING gin (tags);

-- +goose Down
DROP INDEX IF EXISTS idx_series_tags;
DROP INDEX IF EXISTS idx_media_items_tags;
ALTER TABLE series DROP COLUMN IF EXISTS tags;
ALTER TABLE media_items DROP COLUMN IF EXISTS tags;
