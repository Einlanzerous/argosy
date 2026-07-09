// Package discovery advertises the Argosy server on the local network via
// mDNS/DNS-SD (`_argosy._tcp`), so a brand-new device (TV or phone) can find
// the server and start PIN pairing without anyone typing a server address
// (ARGY-123). Advertising is best-effort: on networks where multicast doesn't
// reach (client/AP isolation, container bridge networks, tailnets), clients
// fall back to manual address entry.
package discovery

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"strconv"

	"github.com/Einlanzerous/argosy/internal/version"
	"github.com/libp2p/zeroconf/v2"
)

// ServiceType is the DNS-SD service type Argosy advertises and clients browse.
const ServiceType = "_argosy._tcp"

// Advertise registers the mDNS service and blocks until ctx is done. It never
// returns a hard error to the caller's main loop — a LAN where multicast is
// unavailable should not take the server down — so failures are just logged.
func Advertise(ctx context.Context, addr, serverName string, logger *slog.Logger) {
	port, err := listenPort(addr)
	if err != nil {
		logger.Warn("mdns: not advertising", "err", err)
		return
	}
	txt := []string{
		"name=" + serverName,
		"version=" + version.Version,
		"api=/api/v1",
	}
	srv, err := zeroconf.Register(serverName, ServiceType, "local.", port, txt, nil)
	if err != nil {
		logger.Warn("mdns: advertising failed", "err", err)
		return
	}
	logger.Info("mdns: advertising", "service", ServiceType, "name", serverName, "port", port)
	<-ctx.Done()
	srv.Shutdown()
}

// listenPort extracts the TCP port from a listen address like ":8096" or
// "0.0.0.0:8096". mDNS advertises a port, not a bind address.
func listenPort(addr string) (int, error) {
	_, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return 0, fmt.Errorf("cannot derive advertise port from addr %q: %w", addr, err)
	}
	port, err := strconv.Atoi(portStr)
	if err != nil || port <= 0 {
		return 0, fmt.Errorf("cannot derive advertise port from addr %q", addr)
	}
	return port, nil
}
