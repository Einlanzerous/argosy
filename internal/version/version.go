// Package version exposes the build version, overridable via -ldflags.
package version

// Version is the build version. Override at build time with:
//
//	go build -ldflags "-X github.com/Einlanzerous/argosy/internal/version.Version=$(git describe --tags --always)"
var Version = "dev"
