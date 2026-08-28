# syntax=docker/dockerfile:1

# Production image: one self-contained artifact. The Vue SPA is built and
# embedded into the Go binary (go:embed), then dropped onto a slim base that
# carries ffmpeg/ffprobe. Build from the repo root:
#   docker build -f deploy/Dockerfile -t argosy:latest .

# 1) Build the Vue SPA -> internal/webui/dist
# Pin bun to match CI (.github/workflows/ci.yml). A floating "1-debian" pulls a
# newer bun that breaks vue-tsc's .vue module resolution at `bun run build`.
FROM oven/bun:1.3.14-debian AS web
WORKDIR /app/web
COPY web/package.json web/bun.lock ./
RUN bun install --frozen-lockfile
COPY web/ ./
RUN bun run build

# 2) Build the Go binary with the SPA embedded
FROM golang:1.26-trixie AS build
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
COPY --from=web /app/internal/webui/dist ./internal/webui/dist
# Build identity (ARGY-213). Stamped into the binary and reported by /healthz,
# which Switchyard's delivery reconciler polls to record what is actually
# running (the SWY-192 contract, rolled out by SERV-128).
#
# Both default to EMPTY, not to a placeholder like "docker". The old "docker"
# default put that literal string where a version belongs for every hand-built
# image; `internal/version` maps empty back to "dev", which is the same rule
# that already had to cover an ARG declared but never passed — one that expands
# to an empty string regardless of what default is written here.
#
# There is deliberately no default of the release version: an image built
# outside the publish workflow must not be able to claim it is a release.
#
# VERSION is bare semver, no "v" prefix — it is compared with strict equality
# against org.opencontainers.image.version, which metadata-action stamps bare.
# GIT_SHA is the full 40-char commit; /healthz reports it verbatim.
ARG VERSION=
ARG GIT_SHA=
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w \
      -X github.com/Einlanzerous/argosy/internal/version.Version=${VERSION} \
      -X github.com/Einlanzerous/argosy/internal/version.Commit=${GIT_SHA}" \
    -o /out/argosy ./cmd/argosy

# 3) Runtime: slim base + ffmpeg + the VAAPI drivers for both GPUs (ARGY-183).
#
# The hardware encode path is VAAPI, not QSV. ffmpeg 7 dropped libmfx entirely
# and speaks only to Intel's VPL runtime, which supports Gen12+ silicon — the
# UHD 630 in this box is Gen9.5, so `h264_qsv` fails to create an MFX session on
# trixie no matter which packages are installed. VAAPI drives the same iGPU and
# covers everything the ladder needs (H.264, HEVC Main and Main10).
#
# Two VA drivers ship because there are two GPUs: intel-media-va-driver-non-free
# (iHD) for the iGPU, mesa-va-drivers (radeonsi) for the discrete AMD card that
# Probe falls back to. Deliberately no LIBVA_DRIVER_NAME — forcing iHD globally
# would break the AMD device, and libva picks the right driver per render node
# on its own. Pass /dev/dri through at run time (see docker-compose.yml).
#
# ffmpeg is pinned to .ffmpeg-version so CI, dev and prod run the same build;
# the HLS manifest tests assert ffmpeg's output shape, which only guards
# anything if the version under test is the version that ships. When Debian
# retires this exact package the build fails loudly here — that is the point;
# the fix is to move .ffmpeg-version, not to unpin.
FROM debian:trixie-slim AS runtime
COPY .ffmpeg-version /tmp/.ffmpeg-version
RUN sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' \
      /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "ffmpeg=$(tr -d '[:space:]' </tmp/.ffmpeg-version)" \
      ca-certificates \
      intel-media-va-driver-non-free \
      mesa-va-drivers \
      libva2 \
      libva-drm2 \
      vainfo \
 && rm -rf /var/lib/apt/lists/* /tmp/.ffmpeg-version
COPY --from=build /out/argosy /usr/local/bin/argosy
ENV ARGOSY_ADDR=":8096"
EXPOSE 8096

# Health probe (ARGY-216). argosy is the one first-party service whose /healthz
# has a branch that genuinely fires — it answers 503 when Postgres is
# unreachable, where every sibling's endpoint is liveness-only and answers 200
# unconditionally. So this is not a formality: it separates "process up,
# database gone" from "process up, database fine", the state nothing else
# surfaces. Without it argosy sits on assert-healthy.sh's "cannot be seen to
# fail" list, which is how interlock-worker stayed invisibly dead.
#
# It also refuses a container configured with NO database at all, which /healthz
# cannot report on its own — see cmd/argosy/healthcheck.go. That process serves
# the SPA shell and 404s every API route while answering 200 "ok".
#
# It buys visibility, not self-healing: `restart: unless-stopped` restarts
# EXITED containers, not unhealthy ones. `docker ps`, assert-healthy.sh and the
# deploy gate are the consumers.
#
# The probe is the binary itself because this image has no HTTP client at all —
# no curl, no wget, not even busybox — and adding one would mean a package to
# track plus a second definition of "healthy" written in shell. `argosy
# healthcheck` reads the contract the handler writes, and a test drives both
# halves together (internal/server/health_test.go) so they cannot drift.
#
# It is declared here rather than only in construct-server's compose so the
# image is probeable wherever it runs; a compose-level healthcheck overrides
# this one, so a better probe later is still free to land there.
#
# start-period covers migrations plus transcode.Probe, which runs a real one-
# frame encode on each render node before the server listens (ARGY-183).
# --timeout exceeds the probe's own 4s deadline so a slow answer is reported by
# the probe in its own words instead of being killed with an empty health log.
HEALTHCHECK --interval=30s --timeout=6s --start-period=90s --retries=3 \
  CMD ["argosy", "healthcheck"]

ENTRYPOINT ["argosy"]
