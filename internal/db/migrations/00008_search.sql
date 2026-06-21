-- +goose Up
-- Full-text search (ARGY-39). Each item carries a generated STORED `search_vector`
-- built from its effective searchable text: base + override + provider titles,
-- overview, genres, and tags. Weighted title=A, tags+genres=B, overview=C so a
-- title hit outranks a body hit. The two-arg to_tsvector(regconfig, text) form is
-- IMMUTABLE (the config is a constant), which a generated column requires; STORED
-- keeps the vector self-maintaining across rescans with no triggers, and the GIN
-- index makes `@@` matching fast on a large library.
--
-- People/cast are intentionally absent: TMDB credits aren't ingested yet (ARGY-39
-- defers people). When they land, add them here at weight B and the STORED column
-- backfills on the next write (or a column rebuild).
--
-- Tags use array_to_tsvector (immutable) rather than array_to_string (STABLE under
-- locale, which a generated column rejects). It stores each tag as a verbatim
-- lexeme; tags are normalized lowercase at ingest (Stevedore), so a lowercased
-- query tsquery matches them.

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

-- +goose Down
DROP INDEX IF EXISTS idx_series_search;
ALTER TABLE series DROP COLUMN IF EXISTS search_vector;
DROP INDEX IF EXISTS idx_media_items_search;
ALTER TABLE media_items DROP COLUMN IF EXISTS search_vector;
