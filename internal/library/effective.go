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

func mfloat(m map[string]any, k string) (float64, bool) {
	switch n := m[k].(type) {
	case float64:
		return n, true
	case int:
		return float64(n), true
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

// effectiveRating returns the provider rating (vote_average, 0–10), override
// blob winning over provider, or nil when neither carries one.
func effectiveRating(over, prov map[string]any) *float64 {
	if v, ok := mfloat(over, "vote_average"); ok {
		return &v
	}
	if v, ok := mfloat(prov, "vote_average"); ok {
		return &v
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

// backdropURL resolves the cached landscape backdrop (for full-screen heroes),
// or nil when none was fetched — callers fall back to the poster.
func backdropURL(base string, over, prov map[string]any) *string {
	rel := firstNonEmpty(mstr(over, "backdrop"), mstr(prov, "backdrop"))
	if rel == "" {
		return nil
	}
	u := base + "/" + rel
	return &u
}

// stillURL resolves an episode's cached still (16:9 landscape thumbnail), or nil
// when none was fetched — callers fall back to the hatch placeholder.
func stillURL(base string, over, prov map[string]any) *string {
	rel := firstNonEmpty(mstr(over, "still"), mstr(prov, "still"))
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

// f32 narrows an optional float64 to the float32 the generated API types use.
func f32(v *float64) *float32 {
	if v == nil {
		return nil
	}
	f := float32(*v)
	return &f
}

// nonNil normalizes a nil slice to an empty one so required JSON arrays
// serialize as [] rather than null.
func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}
