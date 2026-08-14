-- +goose Up
-- Stow: offline downloads (ARGY-49). A stow job exists only for the *packaging*
-- half of the feature. The decision is per item (see planStow): a source that is
-- already phone-friendly and small enough is handed over as-is through the
-- existing range-capable /items/{id}/stream, which needs no server state at all
-- — no row is written for that path. A source that must be re-encoded gets one
-- row here, tracking the ffmpeg run that produces a single progressive MP4.
--
-- The row is the queue, the progress feed, and the retention record: it outlives
-- the request that created it (a 40-minute encode has no client attached), and
-- it is what tells Ballast the artifact directory is still spoken for.
CREATE TABLE stow_jobs (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The requesting household account, not the catalog owner: one member's
    -- stow must not be visible to — or cancellable by — another. Mirrors how
    -- transcode sessions are scoped (accountOf vs catalogOf).
    account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    item_id      uuid NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
    -- pending (queued behind the concurrency limit) | packaging | ready | failed.
    state        text NOT NULL,
    encoder      text NOT NULL DEFAULT '',
    output_bytes bigint NOT NULL DEFAULT 0,
    -- Source duration, so progress_ms can be reported as a percentage without
    -- the client re-deriving it.
    duration_seconds double precision NOT NULL DEFAULT 0,
    progress_ms  bigint NOT NULL DEFAULT 0,
    error        text NOT NULL DEFAULT '',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    ready_at     timestamptz
);

-- One job per (account, item): a repeat stow of the same item joins the job
-- already running rather than spawning a second ffmpeg over the same source.
-- A failed job is retried by resetting this row, not by inserting beside it.
CREATE UNIQUE INDEX stow_jobs_account_item ON stow_jobs (account_id, item_id);
-- The queue scan (pending → packaging) and the boot-time stale reset both key
-- on state.
CREATE INDEX stow_jobs_state ON stow_jobs (state);

-- +goose Down
DROP TABLE stow_jobs;
