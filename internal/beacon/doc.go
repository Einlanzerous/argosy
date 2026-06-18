// Package beacon broadcasts live play-state changes to connected devices for
// cross-device resume (Phase 4), via Postgres LISTEN/NOTIFY fanned out over
// SSE/WebSocket.
package beacon
