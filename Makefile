SHELL := /bin/bash
GO ?= go
NPM ?= npm
WEB := web
EMBED_DIR := internal/webui/dist
BIN := bin/argosy
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -X github.com/Einlanzerous/argosy/internal/version.Version=$(VERSION)
COMPOSE := docker compose -f deploy/docker-compose.yml
GO_PKGS := ./cmd/... ./internal/...   # scope go tooling; keep it out of web/node_modules

.PHONY: all build web-build go-build ensure-embed server-dev web-dev lint fmt test tidy generate clean help \
	compose-up compose-web compose-down compose-logs compose-reset seed docker-build

all: build

build: web-build go-build ## Build the single artifact: web UI embedded into the server binary

web-build: ## Build the Vue SPA into the Go embed dir (internal/webui/dist)
	cd $(WEB) && $(NPM) install && $(NPM) run build
	@touch $(EMBED_DIR)/.gitkeep   # Vite's emptyOutDir wipes it; keep it tracked

ensure-embed: ## Guarantee the embed dir is non-empty so go:embed compiles
	@mkdir -p $(EMBED_DIR)
	@[ -n "$$(ls -A $(EMBED_DIR) 2>/dev/null)" ] || touch $(EMBED_DIR)/.gitkeep

go-build: ensure-embed ## Build the server binary (embeds whatever is in the embed dir)
	$(GO) build -ldflags "$(LDFLAGS)" -o $(BIN) ./cmd/argosy

server-dev: ensure-embed ## Run the Go server (serves a placeholder until the web is built)
	$(GO) run ./cmd/argosy

web-dev: ## Run the Vite dev server with HMR (proxies API/stream routes to :8096)
	cd $(WEB) && $(NPM) install && $(NPM) run dev

compose-up: ## Start the dev stack: Postgres + server (air hot-reload) on :8096
	$(COMPOSE) up -d --build

compose-web: ## Start the dev stack incl. the Vite dev server (HMR) on :5173
	$(COMPOSE) --profile webdev up -d --build

compose-logs: ## Tail dev stack logs
	$(COMPOSE) logs -f

compose-down: ## Stop the dev stack
	$(COMPOSE) down

compose-reset: ## Stop the dev stack and delete volumes (drops the DB!)
	$(COMPOSE) down -v

seed: ## Seed the dev database with a demo account + two profiles
	$(COMPOSE) exec -T db sh -c 'psql -v ON_ERROR_STOP=1 -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"' < internal/db/seed.sql

docker-build: ## Build the production single-artifact image (argosy:dev)
	docker build -f deploy/Dockerfile -t argosy:dev --build-arg VERSION=$(VERSION) .

lint: ## Lint Go and web
	$(GO) vet $(GO_PKGS)
	@command -v golangci-lint >/dev/null 2>&1 && golangci-lint run $(GO_PKGS) || echo "golangci-lint not installed; skipping"
	cd $(WEB) && $(NPM) run lint

fmt: ## Format Go and web
	$(GO) fmt $(GO_PKGS)
	cd $(WEB) && $(NPM) run format

test: ensure-embed ## Run Go tests
	$(GO) test $(GO_PKGS)

tidy: ## Tidy go.mod
	$(GO) mod tidy

generate: ## Regenerate the Go server interface + TS client from the OpenAPI spec
	$(GO) tool oapi-codegen -config proto/openapi/oapi-codegen.yaml proto/openapi/argosy.yaml
	cd $(WEB) && $(NPM) install && $(NPM) run gen:api

clean: ## Remove build artifacts (restores the embed placeholder)
	rm -rf bin $(EMBED_DIR)
	@mkdir -p $(EMBED_DIR) && touch $(EMBED_DIR)/.gitkeep

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
