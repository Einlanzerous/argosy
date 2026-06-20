-- +goose Up
-- Fleet (P4, ARGY-33): capture the client platform/type at device registration
-- so the Fleet can show what each device is (web / phone / tv / ...), beyond
-- guessing from the name.
ALTER TABLE devices ADD COLUMN platform text;

-- +goose Down
ALTER TABLE devices DROP COLUMN IF EXISTS platform;
