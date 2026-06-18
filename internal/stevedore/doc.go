// Package stevedore is the media ingestion worker (Phase 1): it scans library
// sources, extracts ffprobe metadata, classifies film vs. series, and keeps the
// Manifest current. It is written against a storage interface rather than the
// filesystem directly, so local FS and Pydio Cells back-ends are swappable
// (see ARGY-15 / ARGY-53).
package stevedore
