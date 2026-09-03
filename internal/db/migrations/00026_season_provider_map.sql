-- +goose Up
-- Translate the metadata provider's season numbering onto ours (ARGY-224).
--
-- The on-disk layout comes from Sonarr, which is TVDB-ordered; TMDB numbers the
-- same show differently whenever it consolidates or splits what TVDB does not.
-- Bleach is the worked example: TVDB gives Thousand-Year Blood War its own
-- season 17, TMDB files it as season 2 of a three-season show. Asking TMDB for
-- "season 17" 404s, so every episode was created from its filename and left with
-- an empty provider_metadata — silently, since the *series* still matched.
--
-- The database stays the source of truth for what the library looks like:
-- season_number keeps meaning the season on disk, and the provider's numbering
-- becomes a lookup key hanging off it. Nothing here renumbers anything.
ALTER TABLE seasons
    -- The provider season to read this season's episodes from. NULL = unresolved
    -- (nothing has looked yet, or the lookup found no counterpart).
    ADD COLUMN provider_season_number int,
    -- Added to the on-disk episode number to get the provider's. Needed because
    -- the collapse is rarely 1:1 at the season boundary: TVDB S3 is TMDB S1
    -- E42-E63, so the season number alone would point every episode at S1E1 and
    -- write confidently wrong titles — worse than the empty ones this fixes.
    ADD COLUMN provider_episode_offset int NOT NULL DEFAULT 0,
    -- How the mapping above was arrived at, so it is inspectable and so the
    -- automatic pass knows what it may overwrite:
    --   identity      — the provider numbers this season the same way we do
    --   episode_group — taken from the provider's TVDB-ordered episode group
    --   manual        — set by an operator; the resolver must never clobber it
    ADD COLUMN provider_season_source text
        CHECK (provider_season_source IN ('identity', 'episode_group', 'manual'));

-- +goose Down
ALTER TABLE seasons
    DROP COLUMN provider_season_number,
    DROP COLUMN provider_episode_offset,
    DROP COLUMN provider_season_source;
