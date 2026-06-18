package library

import (
	"encoding/json"

	"github.com/google/uuid"
	openapi_types "github.com/oapi-codegen/runtime/types"
)

// Effective metadata = provider_metadata (base) overlaid by metadata (override).
// These helpers pull typed fields with override-wins precedence.

func decodeMap(raw []byte) map[string]any {
	m := map[string]any{}
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &m)
	}
	return m
}

func mstr(m map[string]any, k string) string {
	if s, ok := m[k].(string); ok {
		return s
	}
	return ""
}

func mint(m map[string]any, k string) (int, bool) {
	switch n := m[k].(type) {
	case float64:
		return int(n), true
	case int:
		return n, true
	}
	return 0, false
}

func mstrs(m map[string]any, k string) []string {
	arr, ok := m[k].([]any)
	if !ok {
		return nil
	}
	var out []string
	for _, e := range arr {
		if s, ok := e.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

func effectiveTitle(over, prov map[string]any, fallback string) string {
	return firstNonEmpty(mstr(over, "title"), mstr(prov, "title"), fallback)
}

func effectiveYear(over, prov map[string]any, fallback *int) *int {
	if y, ok := mint(over, "year"); ok {
		return &y
	}
	if y, ok := mint(prov, "year"); ok {
		return &y
	}
	return fallback
}

func effectiveOverview(over, prov map[string]any) *string {
	if s := firstNonEmpty(mstr(over, "overview"), mstr(prov, "overview")); s != "" {
		return &s
	}
	return nil
}

func effectiveGenres(over, prov map[string]any) *[]string {
	if g := mstrs(over, "genres"); len(g) > 0 {
		return &g
	}
	if g := mstrs(prov, "genres"); len(g) > 0 {
		return &g
	}
	return nil
}

func posterURL(base string, over, prov map[string]any) *string {
	rel := firstNonEmpty(mstr(over, "poster"), mstr(prov, "poster"))
	if rel == "" {
		return nil
	}
	u := base + "/" + rel
	return &u
}

func parseUUID(s string) openapi_types.UUID {
	u, _ := uuid.Parse(s)
	return u
}
