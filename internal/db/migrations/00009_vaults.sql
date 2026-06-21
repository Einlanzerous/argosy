-- +goose Up
-- Vaults (ARGY-42): user-curated collections of films + series. A vault is owned
-- by one profile and is either personal (owner-only) or shared with the whole
-- household (any member can curate its items). An item references exactly one of
-- a media_item (a film) or a series — enforced by the check + the partial unique
-- indexes that also prevent the same title being added twice.

CREATE TABLE vaults (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    owner_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name          text NOT NULL,
    description   text,
    shared        boolean NOT NULL DEFAULT false,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_vaults_account ON vaults (account_id);
CREATE INDEX idx_vaults_owner ON vaults (owner_user_id);

CREATE TABLE vault_items (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id      uuid NOT NULL REFERENCES vaults(id) ON DELETE CASCADE,
    media_item_id uuid REFERENCES media_items(id) ON DELETE CASCADE,
    series_id     uuid REFERENCES series(id) ON DELETE CASCADE,
    position      int NOT NULL DEFAULT 0,
    added_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT vault_item_one_ref CHECK ((media_item_id IS NOT NULL) <> (series_id IS NOT NULL))
);
CREATE INDEX idx_vault_items_vault ON vault_items (vault_id, position);
CREATE UNIQUE INDEX idx_vault_items_movie ON vault_items (vault_id, media_item_id) WHERE media_item_id IS NOT NULL;
CREATE UNIQUE INDEX idx_vault_items_series ON vault_items (vault_id, series_id) WHERE series_id IS NOT NULL;

-- +goose Down
DROP TABLE IF EXISTS vault_items;
DROP TABLE IF EXISTS vaults;
