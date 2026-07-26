-- +goose Up
-- Account lifecycle (ARGY-86). Creation is covered (Purser provisioning +
-- first-run bootstrap); this adds the rest of the lifecycle: an account can be
-- disabled (kept, but can't sign in and its devices stop authenticating) and
-- every account/profile mutation leaves an audit row — the prod DB previously
-- had no trail at all (cf. the kglawrence SQL-insert incident this ticket was
-- filed over).
ALTER TABLE accounts ADD COLUMN disabled_at timestamptz;

-- Append-only. Deliberately no FKs: deleting an account must not erase the
-- record of who deleted it (or of anything it ever did).
CREATE TABLE audit_log (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at      timestamptz NOT NULL DEFAULT now(),
    -- 'session' (a signed-in device), 'provision' (X-Provision-Token caller),
    -- 'system' (startup bootstrap / first-login flows).
    actor_type       text NOT NULL,
    actor_account_id uuid,
    actor_user_id    uuid,
    action           text NOT NULL,  -- e.g. 'account.disable', 'profile.create'
    target_type      text NOT NULL,  -- 'account' | 'profile'
    target_id        uuid,
    detail           jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX audit_log_occurred_at ON audit_log (occurred_at);

-- +goose Down
DROP TABLE audit_log;
ALTER TABLE accounts DROP COLUMN disabled_at;
