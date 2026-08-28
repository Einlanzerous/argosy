package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/health"
)

// probeTimeout bounds the whole check.
//
// It has to exceed the handler's own database ping, which is capped at 2s in
// internal/server.healthHandler — otherwise the probe would time out on exactly
// the degraded case it exists to catch and report a connection error instead of
// the 503. And it has to stay under the Dockerfile's HEALTHCHECK --timeout, so
// a slow answer is reported by the probe in its own words rather than the
// process being killed mid-request with nothing in the health log.
const probeTimeout = 4 * time.Second

// runHealthcheck is `argosy healthcheck`: the container's HEALTHCHECK probe
// (ARGY-216). It returns the process exit code — 0 healthy, 1 not.
//
// argosy is the one first-party service whose /healthz has a branch that
// genuinely fires: it answers 503 when Postgres is unreachable, where every
// sibling's health endpoint is liveness-only and answers 200 unconditionally.
// So this distinguishes "process up, database gone" from "process up, database
// fine", which is the state that matters and the one nothing else surfaces.
//
// What it does NOT do is heal anything: `restart: unless-stopped` restarts
// exited containers, not unhealthy ones. This buys visibility — `docker ps`,
// construct-server's assert-healthy.sh, the deploy gate — and that is the point.
func runHealthcheck(cfg config.Config) int {
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout)
	defer cancel()

	rep, err := health.Probe(ctx, nil, health.URL(cfg.Addr))
	if err != nil {
		// Docker keeps the last few probes' combined output in
		// .State.Health.Log, so this line is the entire diagnosis available to
		// `docker inspect` after a container goes unhealthy. Make it say which
		// of the two failures it was.
		fmt.Fprintf(os.Stderr, "unhealthy: %v\n", err)
		return 1
	}
	// Naming the build on the healthy path too, because the health log is then
	// a free record of what has been answering and since when.
	fmt.Printf("ok version=%s\n", rep.Version)
	return 0
}
