-- +goose Up
-- Account -> users (profiles) -> devices, plus the media model and play_state.
-- play_state keys on (user_id, media_item_id) so cross-device resume never
-- bleeds across household members.

CREATE TABLE accounts (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- role is the admin/viewer permissions stub (unenforced until ARGY-12/P4).
CREATE TABLE users (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       text NOT NULL,
    role       text NOT NULL DEFAULT 'viewer' CHECK (role IN ('admin', 'viewer')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (account_id, name)
);
CREATE INDEX idx_users_account ON users (account_id);

CREATE TABLE devices (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    user_id      uuid REFERENCES users(id) ON DELETE SET NULL,
    name         text NOT NULL,
    token_hash   text NOT NULL UNIQUE,
    last_seen_at timestamptz,
    revoked_at   timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_account ON devices (account_id);
CREATE INDEX idx_devices_user ON devices (user_id);

CREATE TABLE libraries (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name       text NOT NULL,
    kind       text NOT NULL DEFAULT 'mixed' CHECK (kind IN ('movie', 'show', 'mixed')),
    root_path  text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_libraries_account ON libraries (account_id);

-- A playable file: a movie, or the file backing a series episode.
CREATE TABLE media_items (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id       uuid NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    kind             text NOT NULL CHECK (kind IN ('movie', 'episode')),
    title            text NOT NULL,
    sort_title       text,
    year             int,
    content_hash     text,
    file_path        text NOT NULL,
    container        text,
    duration_seconds double precision,
    metadata         jsonb NOT NULL DEFAULT '{}'::jsonb,  -- override blob (NFO/sidecar/manual)
    technical        jsonb NOT NULL DEFAULT '{}'::jsonb,  -- raw ffprobe output
    added_at         timestamptz NOT NULL DEFAULT now(),
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (library_id, file_path)
);
CREATE INDEX idx_media_items_library ON media_items (library_id);
CREATE INDEX idx_media_items_content_hash ON media_items (content_hash);
CREATE INDEX idx_media_items_metadata ON media_items USING gin (metadata);

CREATE TABLE series (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id uuid NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    title      text NOT NULL,
    sort_title text,
    year       int,
    metadata   jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_series_library ON series (library_id);

CREATE TABLE seasons (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    series_id     uuid NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    season_number int NOT NULL,
    title         text,
    metadata      jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (series_id, season_number)
);

CREATE TABLE episodes (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    season_id      uuid NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
    media_item_id  uuid REFERENCES media_items(id) ON DELETE SET NULL,
    episode_number int NOT NULL,
    title          text,
    metadata       jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (season_id, episode_number)
);
CREATE INDEX idx_episodes_media_item ON episodes (media_item_id);

CREATE TABLE play_state (
    user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    media_item_id    uuid NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
    position_seconds double precision NOT NULL DEFAULT 0,
    duration_seconds double precision,
    watched          boolean NOT NULL DEFAULT false,
    updated_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, media_item_id)
);
CREATE INDEX idx_play_state_user ON play_state (user_id);

-- +goose Down
DROP TABLE IF EXISTS play_state;
DROP TABLE IF EXISTS episodes;
DROP TABLE IF EXISTS seasons;
DROP TABLE IF EXISTS series;
DROP TABLE IF EXISTS media_items;
DROP TABLE IF EXISTS libraries;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS accounts;
