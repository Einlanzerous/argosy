// Package httpx holds the shared HTTP response helpers used across the Argosy
// API handlers, so JSON and error responses are written one consistent way.
// Error bodies use the generated api.Error type, keeping every error response
// conformant with the OpenAPI Error schema.
package httpx

import (
	"encoding/json"
	"net/http"

	"github.com/Einlanzerous/argosy/internal/api"
)

// JSON writes v as a JSON response with the given status code.
func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// Error writes msg as a spec-conformant error body ({"error": "..."}) with the
// given status code.
func Error(w http.ResponseWriter, status int, msg string) {
	JSON(w, status, api.Error{Error: msg})
}
