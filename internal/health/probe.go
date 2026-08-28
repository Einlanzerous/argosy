// Package health probes a running Argosy's `GET /healthz` and decides whether
// the answer means "healthy".
//
// It exists so the container's HEALTHCHECK can be the argosy binary itself. The
// runtime image (deploy/Dockerfile) is debian-slim plus ffmpeg and carries no
// HTTP client at all — no curl, no wget, not even busybox — so a probe would
// otherwise mean adding a package to track and writing a second, separate
// definition of "healthy" in shell. The binary is already in the image and
// already owns the contract (ARGY-216).
package health

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
)

// StatusOK is the only `status` /healthz reports when the process is serving
// AND its database answered. Anything else — "degraded" today, whatever a
// future dependency check adds tomorrow — is not healthy.
const StatusOK = "ok"

// DefaultPort matches config.Load's ARGOSY_ADDR default, and is what URL falls
// back to when it is handed an address it cannot parse.
const DefaultPort = "8096"

// maxBody caps what the probe will read. /healthz answers three short fields;
// anything larger is something other than the contract, and a probe should not
// be the thing that reads it all into memory.
const maxBody = 8 << 10

// Report is the /healthz body as a probe reads it — the same wire shape
// internal/server.healthResponse writes, on both the 200 and the 503 path.
type Report struct {
	Status  string  `json:"status"`
	Version string  `json:"version"`
	SHA     *string `json:"sha"`
}

// defaultClient deliberately does NOT use http.DefaultTransport. That reads
// HTTP_PROXY/HTTPS_PROXY from the environment, and a proxy configured for the
// application's outbound calls (TMDB, OpenSubtitles) would then be asked to
// relay a probe to the container's own loopback. The zero Transport has a nil
// Proxy, which is what a same-host probe wants. Timeouts stay on the context so
// the caller owns the deadline.
var defaultClient = &http.Client{Transport: &http.Transport{}}

// URL turns a listen address into the /healthz URL to probe on this host.
//
// The wildcard forms are the point: the server binds ":8096" (or "0.0.0.0:8096"),
// and a probe running inside the same container has to turn that into a real
// destination. Loopback is correct for both — the container listens on every
// interface, and 127.0.0.1 is the one address that is certainly one of them.
func URL(addr string) string {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		// Only genuinely malformed input reaches here — SplitHostPort parses
		// ":8096" happily. A bare port and a bare host are the two shapes worth
		// honouring; anything else takes the default and will fail loudly at
		// connect time, which is the right way for a probe to be wrong.
		if isAllDigits(addr) {
			host, port = "", addr
		} else {
			host, port = addr, DefaultPort
		}
	}
	switch host {
	case "", "0.0.0.0", "::":
		host = "127.0.0.1"
	}
	return "http://" + net.JoinHostPort(host, port) + "/healthz"
}

func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	return strings.IndexFunc(s, func(r rune) bool { return r < '0' || r > '9' }) < 0
}

// Probe GETs url and reports what answered. A nil error means healthy: HTTP 200
// AND a body that names itself "ok".
//
// Every other outcome is an error — a refused connection, the 503 the database
// ping produces, a 200 whose body isn't the contract. That direction is the
// whole value of the check. The failure this has to avoid is not a false alarm
// but a probe that cannot tell and votes "healthy" anyway; construct-server has
// watched a probe whose own dependency was broken exit 0 and report a dead
// service up for as long as anyone cared to look. Uncertainty is unhealthy.
//
// The Report comes back even on the error paths whenever the body decoded, so a
// caller can name the version of the thing that is failing.
//
// Pass a nil client for the default (no proxy, deadline from ctx).
func Probe(ctx context.Context, client *http.Client, url string) (Report, error) {
	if client == nil {
		client = defaultClient
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return Report{}, fmt.Errorf("build request for %s: %w", url, err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return Report{}, fmt.Errorf("GET %s: %w", url, err)
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
	if err != nil {
		return Report{}, fmt.Errorf("GET %s: reading body: %w", url, err)
	}

	// Decoded before the status code is judged, not after: the 503 path carries
	// the same body shape as the 200, so the degraded answer can still name its
	// version — which is the state someone most wants the build identity for
	// (ARGY-213).
	var rep Report
	decodeErr := json.Unmarshal(body, &rep)

	if resp.StatusCode != http.StatusOK {
		if decodeErr == nil && rep.Status != "" {
			return rep, fmt.Errorf("GET %s: HTTP %d, status %q", url, resp.StatusCode, rep.Status)
		}
		return rep, fmt.Errorf("GET %s: HTTP %d", url, resp.StatusCode)
	}
	if decodeErr != nil {
		return rep, fmt.Errorf("GET %s: HTTP 200 but the body is not the /healthz contract: %w", url, decodeErr)
	}
	if rep.Status != StatusOK {
		return rep, fmt.Errorf("GET %s: HTTP 200 with status %q, want %q", url, rep.Status, StatusOK)
	}
	return rep, nil
}
