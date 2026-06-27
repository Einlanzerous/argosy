-- +goose Up
-- People/cast search (ARGY-67). Migration 00008 left a weight-B slot for cast;
-- now that the matcher ingests TMDB credits into provider_metadata.cast, fold
-- those names into the generated search_vector at weight B (alongside tags +
-- genres) so an actor/director query lands the films/series they're in, ranked
-- below title (A) and above overview (C). provider_metadata ->> 'cast' renders
-- the JSON name array as text; to_tsvector tokenizes the names (brackets/quotes
-- aren't word chars). A generated column's expression can't be altered in place,
-- so drop + recreate it (and its GIN index); STORED rebuilds every row on
-- creation, so existing cast data is indexed immediately.

DROP INDEX IF EXISTS idx_media_items_search;
ALTER TABLE media_items DROP COLUMN IF EXISTS search_vector;
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

DROP INDEX IF EXISTS idx_series_search;
ALTER TABLE series DROP COLUMN IF EXISTS search_vector;
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

-- +goose Down
-- Restore the 00008 expression (without cast).
DROP INDEX IF EXISTS idx_series_search;
ALTER TABLE series DROP COLUMN IF EXISTS search_vector;
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
      coalesce(provider_metadata ->> 'genres', '')), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'overview', '') || ' ' ||
      coalesce(provider_metadata ->> 'overview', '')), 'C')
  ) STORED;
CREATE INDEX idx_series_search ON series USING gin (search_vector);

DROP INDEX IF EXISTS idx_media_items_search;
ALTER TABLE media_items DROP COLUMN IF EXISTS search_vector;
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
      coalesce(provider_metadata ->> 'genres', '')), 'B') ||
    setweight(to_tsvector('simple',
      coalesce(metadata ->> 'overview', '') || ' ' ||
      coalesce(provider_metadata ->> 'overview', '')), 'C')
  ) STORED;
CREATE INDEX idx_media_items_search ON media_items USING gin (search_vector);
