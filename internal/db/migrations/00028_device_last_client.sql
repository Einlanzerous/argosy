-- +goose Up
-- ARGY-262: remember which client build each device last spoke as, so the Fleet
-- can show who is behind without anyone asking "what version are you on?".
-- Written by the auth middleware from the X-Argosy-Client request header, and
-- only when the value changes or the stored one is stale (see auth/client.go).
ALTER TABLE devices ADD COLUMN last_client text;
ALTER TABLE devices ADD COLUMN last_client_at timestamptz;

-- +goose Down
ALTER TABLE devices DROP COLUMN IF EXISTS last_client_at;
ALTER TABLE devices DROP COLUMN IF EXISTS last_client;
