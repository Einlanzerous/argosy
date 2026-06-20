# syntax=docker/dockerfile:1

# Production image: one self-contained artifact. The Vue SPA is built and
# embedded into the Go binary (go:embed), then dropped onto a slim base that
# carries ffmpeg/ffprobe. Build from the repo root:
#   docker build -f deploy/Dockerfile -t argosy:latest .

# 1) Build the Vue SPA -> internal/webui/dist
FROM oven/bun:1-debian AS web
WORKDIR /app/web
COPY web/package.json web/bun.lock ./
RUN bun install --frozen-lockfile
COPY web/ ./
RUN bun run build

# 2) Build the Go binary with the SPA embedded
FROM golang:1.26-bookworm AS build
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
COPY --from=web /app/internal/webui/dist ./internal/webui/dist
ARG VERSION=docker
RUN CGO_ENABLED=0 go build \
    -ldflags "-s -w -X github.com/Einlanzerous/argosy/internal/version.Version=${VERSION}" \
    -o /out/argosy ./cmd/argosy

# 3) Runtime: slim base + ffmpeg + Intel QSV/VAAPI runtime (ARGY-30).
# intel-media-va-driver-non-free (iHD) + libmfx provide the QSV path h264_qsv
# talks to; pass /dev/dri through at run time to use it (see docker-compose.yml).
FROM debian:bookworm-slim AS runtime
RUN sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' \
      /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ffmpeg \
      ca-certificates \
      intel-media-va-driver-non-free \
      libmfx1 \
      libva2 \
      libva-drm2 \
      vainfo \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/argosy /usr/local/bin/argosy
ENV ARGOSY_ADDR=":8096" \
    LIBVA_DRIVER_NAME=iHD
EXPOSE 8096
ENTRYPOINT ["argosy"]
