-- +goose Up
-- An item keeps its id when its file is replaced (ARGY-238).
--
-- media_items is keyed on (library_id, file_path), so a Sonarr upgrade that
-- renames the file used to mint a new row and prune the old one — cascading
-- away every profile's play_state and orphaning every stowed copy, which is
-- keyed by the old id. The scanner now matches a vanished row to its
-- replacement and re-points the existing row instead. These columns are what
-- that needs.

-- The file's size as last walked. Two uses: a rename is matched by content only
-- when the size is equal as well as the first-MiB hash (and at least 1 MiB,
-- since below that the hash covers the whole file and every empty placeholder
-- collides), and it is the identity fallback when a hash read fails.
-- NULL until the first sweep after this migration writes it.
ALTER TABLE media_items ADD COLUMN file_size bigint;

-- When a carry onto a replacement file first failed. The row is held back from
-- prune while this is recent, so a transient DB error retries next sweep rather
-- than cascading the row's state away; after an hour it is pruned as before.
-- Cleared whenever the row's file is seen, and by a carry that succeeds. A
-- column rather than updated_at, which the overrides pass and the matcher also
-- write, and rather than a counter, because the scanner is rebuilt every sweep.
ALTER TABLE media_items ADD COLUMN carry_held_since timestamptz;

-- The identity (internal/fileid) of the file a stow package was made from. A job
-- whose source no longer matches its item reports failed rather than handing
-- over an encode of a file the library has replaced.
ALTER TABLE stow_jobs ADD COLUMN source_identity text NOT NULL DEFAULT 'unknown';

-- Exact, because no carry can have happened before this migration: every job
-- was made from its item's current file. It matches fileid.Identity as it reads
-- now — file_size is still NULL everywhere, so a NULL hash is 'unknown'. That
-- holds only until the first sweep writes file_size: an item whose partial hash
-- read had failed then reads as 's<size>', and its ready job reports stale once
-- (one tap to re-stow). Narrow — a NULL hash means a read error — and the
-- scanner's hash stability keeps it from recurring.
UPDATE stow_jobs sj
   SET source_identity = mi.content_hash
  FROM media_items mi
 WHERE mi.id = sj.item_id
   AND mi.content_hash IS NOT NULL
   AND mi.content_hash <> '';

-- +goose Down
ALTER TABLE stow_jobs DROP COLUMN IF EXISTS source_identity;
ALTER TABLE media_items DROP COLUMN IF EXISTS carry_held_since;
ALTER TABLE media_items DROP COLUMN IF EXISTS file_size;
