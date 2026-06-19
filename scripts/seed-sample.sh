#!/usr/bin/env bash
# Seed a sample library into the running dev stack so the UI has real content
# to click through. Files are empty placeholders (ffprobe is best-effort); TMDB
# matches by title/year, so real titles get real posters + metadata.
#
# Titles are Creative-Commons / open films (Blender Foundation et al.) plus a
# couple of well-known ones so the matcher reliably finds artwork.
#
# Prereqs: the dev stack is up (`make compose-up`) and TMDB keys are in
# deploy/.env. Re-running is safe (idempotent: scan/match upsert).
set -euo pipefail
cd "$(dirname "$0")/.."

MEDIA="deploy/sample-media"
COMPOSE="docker compose -f deploy/docker-compose.yml"

echo "→ creating placeholder media under $MEDIA"
mkdir -p "$MEDIA/movies" "$MEDIA/anime" "$MEDIA/shows/Pioneer One/Season 1"

touchfile() { [ -f "$1" ] || : >"$1"; }

# Movies (standalone films)
touchfile "$MEDIA/movies/Big Buck Bunny (2008).mkv"
touchfile "$MEDIA/movies/Sintel (2010).mkv"
touchfile "$MEDIA/movies/Tears of Steel (2012).mkv"
touchfile "$MEDIA/movies/Elephants Dream (2006).mkv"
touchfile "$MEDIA/movies/Cosmos Laundromat (2015).mkv"
touchfile "$MEDIA/movies/Caminandes Llamigos (2016).mkv"

# Anime (films + a series live under anime/ → picks up the 'anime' tag)
touchfile "$MEDIA/anime/Your Name (2016).mkv"
touchfile "$MEDIA/anime/A Silent Voice (2016).mkv"

# A series with episodes
touchfile "$MEDIA/shows/Pioneer One/Season 1/Pioneer One S01E01.mkv"
touchfile "$MEDIA/shows/Pioneer One/Season 1/Pioneer One S01E02.mkv"
touchfile "$MEDIA/shows/Pioneer One/Season 1/Pioneer One S01E03.mkv"

echo "→ scanning /media into a library (attached to the bootstrap account)"
$COMPOSE exec -T server go run ./cmd/argosy scan -name "Main Library" -path /media

echo "→ matching against TMDB for posters + metadata"
$COMPOSE exec -T server go run ./cmd/argosy match

echo "✓ sample library seeded — reload the app to see it."
