-- +goose Up
-- Provider (TMDB) metadata layer, separate from the override blob in `metadata`.
-- Effective metadata = provider_metadata overlaid by metadata (overrides win).
ALTER TABLE media_items ADD COLUMN tmdb_id bigint;
ALTER TABLE media_items ADD COLUMN provider_metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE series ADD COLUMN tmdb_id bigint;
ALTER TABLE series ADD COLUMN provider_metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

-- +goose Down
ALTER TABLE series DROP COLUMN IF EXISTS provider_metadata;
ALTER TABLE series DROP COLUMN IF EXISTS tmdb_id;
ALTER TABLE media_items DROP COLUMN IF EXISTS provider_metadata;
ALTER TABLE media_items DROP COLUMN IF EXISTS tmdb_id;
