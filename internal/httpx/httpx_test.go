package httpx

import (
	"encoding/json"
	"net/http/httptest"
	"testing"
)

func TestJSON(t *testing.T) {
	rec := httptest.NewRecorder()
	JSON(rec, 201, map[string]string{"hello": "world"})

	if rec.Code != 201 {
		t.Errorf("status = %d, want 201", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Errorf("content-type = %q", ct)
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["hello"] != "world" {
		t.Errorf("body = %v", body)
	}
}

func TestError(t *testing.T) {
	rec := httptest.NewRecorder()
	Error(rec, 404, "not found")

	if rec.Code != 404 {
		t.Errorf("status = %d, want 404", rec.Code)
	}
	// The body must match the OpenAPI Error schema: {"error": "..."}.
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(body) != 1 || body["error"] != "not found" {
		t.Errorf("body = %v, want {\"error\":\"not found\"}", body)
	}
}
