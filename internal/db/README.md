# Database schema (v1)

PostgreSQL, applied via [goose](https://github.com/pressly/goose) migrations in
`migrations/` (embedded into the binary; run automatically on startup). Schema
version is tracked in `goose_db_version`.

## Model

```
accounts ──┬── users (profiles)        role: admin | viewer   (permissions stub)
           ├── devices                 token_hash, revoked_at  (per-device auth, ARGY-12)
           └── libraries ──┬── media_items   kind: movie | episode   (the playable file)
                           └── series ── seasons ── episodes ── media_item_id

play_state (user_id, media_item_id)  ← PRIMARY KEY
```

| Table         | Purpose                                                                 |
| ------------- | ----------------------------------------------------------------------- |
| `accounts`    | A household.                                                            |
| `users`       | Profiles under an account. `role` is the admin/viewer permissions stub. |
| `devices`     | Per-device tokens (`token_hash`, revocable) — Fleet management.          |
| `libraries`   | A scanned root (`movie` / `show` / `mixed`).                            |
| `media_items` | A playable file (a movie or an episode's file). JSONB `metadata` (override blob) + `technical` (raw ffprobe). |
| `series` / `seasons` / `episodes` | TV hierarchy; `episodes.media_item_id` points at the file. |
| `play_state`  | Resume position **keyed on `(user_id, media_item_id)`** so resume never bleeds across household members. |

## Key invariants

- `play_state` PK is `(user_id, media_item_id)` — per-user, never global.
- FKs cascade `account → users → devices` and `library → media/series → …`.
- Override metadata lives in JSONB (`media_items.metadata`, GIN-indexed) so NFO/sidecar/manual edits (Phase 1) survive re-scans.
- `gen_random_uuid()` PKs (Postgres core, no extension needed).

## Local

- Migrations run on server startup when a database is configured.
- `make seed` loads a demo account + two profiles (`internal/db/seed.sql`).
- Tests: `internal/db` runs migration/invariant checks against `ARGOSY_TEST_DATABASE_URL` (set in CI; skipped locally when unset).
