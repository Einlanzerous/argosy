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
ARG VERSION=docker
RUN CGO_ENABLED=0 go build \
    -ldflags "-s -w -X github.com/Einlanzerous/argosy/internal/version.Version=${VERSION}" \
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
ENTRYPOINT ["argosy"]
