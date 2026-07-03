-- +goose Up
-- Drop the labels feature (ARGY-110). Genres + full-text keyword search cover
-- discovery, so both flavors of "label" go:
--   * path-derived media taxonomy tags (ARGY-54: the `tags` columns, anime etc.)
--   * per-user custom labels (ARGY-73: the user_labels table)
-- The generated search_vector columns (00008/00018) fold `tags` in at weight B,
-- so they must be rebuilt without tags BEFORE the tags columns can be dropped.

-- Per-user labels: independent, drop outright.
DROP TABLE IF EXISTS user_labels;

-- The search_vector generated columns depend on `tags`; drop them (and their GIN
-- indexes) first, then drop tags, then recreate the vectors without tags.
DROP INDEX IF EXISTS idx_media_items_search;
ALTER TABLE media_items DROP COLUMN IF EXISTS search_vector;
DROP INDEX IF EXISTS idx_series_search;
ALTER TABLE series DROP COLUMN IF EXISTS search_vector;

DROP INDEX IF EXISTS idx_media_items_tags;
DROP INDEX IF EXISTS idx_series_tags;
ALTER TABLE media_items DROP COLUMN IF EXISTS tags;
ALTER TABLE series DROP COLUMN IF EXISTS tags;

-- Recreate the search_vector without the tags weight-B slot (title=A, genres+cast=B,
-- overview=C). STORED rebuilds every row on creation, so the index is complete.
ALTER TABLE media_items
  ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('simple',
      coalesce(title, '') || ' ' ||
      coalesce(sort_title, '') || ' ' ||
      coalesce(metadata ->> 'title', '') || ' ' ||
      coalesce(provider_metadata ->> 'title', '')), 'A') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'cast', '')), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'overview', '') || ' ' ||
      coalesce(provider_metadata ->> 'overview', '')), 'C')
  ) STORED;
CREATE INDEX idx_media_items_search ON media_items USING gin (search_vector);

ALTER TABLE series
  ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('simple',
      coalesce(title, '') || ' ' ||
      coalesce(sort_title, '') || ' ' ||
      coalesce(metadata ->> 'title', '') || ' ' ||
      coalesce(provider_metadata ->> 'title', '')), 'A') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'cast', '')), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'overview', '') || ' ' ||
      coalesce(provider_metadata ->> 'overview', '')), 'C')
  ) STORED;
CREATE INDEX idx_series_search ON series USING gin (search_vector);

-- +goose Down
-- Restore tags columns (empty — path tags repopulate on the next rescan) and the
-- search_vector with the tags weight-B slot, plus the user_labels table.
DROP INDEX IF EXISTS idx_media_items_search;
ALTER TABLE media_items DROP COLUMN IF EXISTS search_vector;
DROP INDEX IF EXISTS idx_series_search;
ALTER TABLE series DROP COLUMN IF EXISTS search_vector;

ALTER TABLE media_items ADD COLUMN tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE series ADD COLUMN tags text[] NOT NULL DEFAULT '{}';
CREATE INDEX idx_media_items_tags ON media_items USING gin (tags);
CREATE INDEX idx_series_tags ON series USING gin (tags);

ALTER TABLE media_items
  ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('simple',
      coalesce(title, '') || ' ' ||
      coalesce(sort_title, '') || ' ' ||
      coalesce(metadata ->> 'title', '') || ' ' ||
      coalesce(provider_metadata ->> 'title', '')), 'A') ||
    setweight(array_to_tsvector(tags), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'cast', '')), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'overview', '') || ' ' ||
      coalesce(provider_metadata ->> 'overview', '')), 'C')
  ) STORED;
CREATE INDEX idx_media_items_search ON media_items USING gin (search_vector);

ALTER TABLE series
  ADD COLUMN search_vector tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('simple',
      coalesce(title, '') || ' ' ||
      coalesce(sort_title, '') || ' ' ||
      coalesce(metadata ->> 'title', '') || ' ' ||
      coalesce(provider_metadata ->> 'title', '')), 'A') ||
    setweight(array_to_tsvector(tags), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'genres', '') || ' ' ||
      coalesce(provider_metadata ->> 'cast', '')), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'overview', '') || ' ' ||
      coalesce(provider_metadata ->> 'overview', '')), 'C')
  ) STORED;
CREATE INDEX idx_series_search ON series USING gin (search_vector);

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
