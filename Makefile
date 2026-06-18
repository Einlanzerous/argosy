SHELL := /bin/bash
GO ?= go
NPM ?= npm
WEB := web
EMBED_DIR := internal/webui/dist
BIN := bin/argosy
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -X github.com/Einlanzerous/argosy/internal/version.Version=$(VERSION)

.PHONY: all build web-build go-build ensure-embed server-dev web-dev lint fmt test tidy clean help

all: build

build: web-build go-build ## Build the single artifact: web UI embedded into the server binary

web-build: ## Build the Vue SPA into the Go embed dir (internal/webui/dist)
	cd $(WEB) && $(NPM) install && $(NPM) run build

ensure-embed: ## Guarantee the embed dir is non-empty so go:embed compiles
	@mkdir -p $(EMBED_DIR)
	@[ -n "$$(ls -A $(EMBED_DIR) 2>/dev/null)" ] || touch $(EMBED_DIR)/.gitkeep

go-build: ensure-embed ## Build the server binary (embeds whatever is in the embed dir)
	$(GO) build -ldflags "$(LDFLAGS)" -o $(BIN) ./cmd/argosy

server-dev: ensure-embed ## Run the Go server (serves a placeholder until the web is built)
	$(GO) run ./cmd/argosy

web-dev: ## Run the Vite dev server with HMR (proxies API/stream routes to :8080)
	cd $(WEB) && $(NPM) install && $(NPM) run dev

lint: ## Lint Go and web
	$(GO) vet ./...
	@command -v golangci-lint >/dev/null 2>&1 && golangci-lint run || echo "golangci-lint not installed; skipping"
	cd $(WEB) && $(NPM) run lint

fmt: ## Format Go and web
	$(GO) fmt ./...
	cd $(WEB) && $(NPM) run format

test: ensure-embed ## Run Go tests
	$(GO) test ./...

tidy: ## Tidy go.mod
	$(GO) mod tidy

clean: ## Remove build artifacts (restores the embed placeholder)
	rm -rf bin $(EMBED_DIR)
	@mkdir -p $(EMBED_DIR) && touch $(EMBED_DIR)/.gitkeep

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
