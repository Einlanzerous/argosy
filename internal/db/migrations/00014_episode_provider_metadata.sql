-- +goose Up
-- Per-episode provider metadata (ARGY-58): TMDB episode name/overview/still are
-- fetched after a series matches and stored here, mirroring the
-- provider_metadata / metadata (override) split used by series + media_items.
-- effectiveOverview etc. read this blob with override-wins precedence.
ALTER TABLE episodes ADD COLUMN provider_metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

-- +goose Down
ALTER TABLE episodes DROP COLUMN IF EXISTS provider_metadata;
