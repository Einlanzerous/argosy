-- +goose Up
-- ARGY-99: give each install a stable identity so a re-pair from the same
-- physical device updates its existing Fleet row instead of inserting a brand
-- new duplicate. Clients persist an install_id across re-pairs and send it on
-- registration; the server upserts on (account_id, install_id).
ALTER TABLE devices ADD COLUMN install_id text;

-- At most one device per (account, install_id) — revoked or not — so a re-pair
-- collapses onto (and un-revokes) the existing row. Partial so legacy rows and
-- any client that doesn't send an install_id keep the insert-every-time path.
CREATE UNIQUE INDEX idx_devices_install ON devices (account_id, install_id)
    WHERE install_id IS NOT NULL;

-- Prune existing cruft (the re-pair duplicates this fix prevents going forward):
-- revoke never-seen orphans older than 7 days. A device only gets last_seen_at
-- once its token is actually used, so a week-old row that never authenticated is
-- abandoned-pairing noise with no presence sessions or playback history.
UPDATE devices SET revoked_at = now()
    WHERE last_seen_at IS NULL
      AND revoked_at IS NULL
      AND created_at < now() - interval '7 days';

-- +goose Down
DROP INDEX IF EXISTS idx_devices_install;
ALTER TABLE devices DROP COLUMN IF EXISTS install_id;
