-- +goose Up
-- Unique series per library (by normalized sort_title) so classification can
-- upsert idempotently; review_required flags items the classifier couldn't place.
CREATE UNIQUE INDEX series_library_sort_title ON series (library_id, sort_title);
ALTER TABLE media_items ADD COLUMN review_required boolean NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE media_items DROP COLUMN IF EXISTS review_required;
DROP INDEX IF EXISTS series_library_sort_title;
