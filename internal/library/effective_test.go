package library

import "testing"

func TestEffectivePrecedence(t *testing.T) {
	prov := map[string]any{
		"title":    "Provider Title",
		"year":     float64(2000),
		"overview": "prov overview",
		"poster":   "movies/1.jpg",
	}
	over := map[string]any{
		"title":  "Override Title",
		"poster": "overrides/x.jpg",
	}

	if got := effectiveTitle(over, prov, "fallback"); got != "Override Title" {
		t.Errorf("title = %q, want override", got)
	}
	if y := effectiveYear(over, prov, nil); y == nil || *y != 2000 {
		t.Errorf("year = %v, want provider 2000 (override has none)", y)
	}
	if ov := effectiveOverview(over, prov); ov == nil || *ov != "prov overview" {
		t.Errorf("overview = %v, want provider", ov)
	}
	if pu := posterURL("/artwork", over, prov); pu == nil || *pu != "/artwork/overrides/x.jpg" {
		t.Errorf("posterURL = %v, want override poster", pu)
	}
	if got := effectiveTitle(map[string]any{}, map[string]any{}, "fb"); got != "fb" {
		t.Errorf("title = %q, want fallback", got)
	}
	if pu := posterURL("/artwork", map[string]any{}, map[string]any{}); pu != nil {
		t.Errorf("posterURL = %v, want nil", pu)
	}
}

// TestEffectiveYearUnknownIsNil pins ARGY-309: a year of 0 (what a TMDB match
// with no release date used to persist) is "unknown", not a value, so it must
// not reach the API as 0 and must not mask a lower-precedence real year.
func TestEffectiveYearUnknownIsNil(t *testing.T) {
	zero := map[string]any{"year": float64(0)}
	ten := 2010
	zeroCol := 0

	if y := effectiveYear(nil, zero, nil); y != nil {
		t.Errorf("provider year 0 = %v, want nil", *y)
	}
	if y := effectiveYear(zero, zero, &zeroCol); y != nil {
		t.Errorf("all-zero = %v, want nil", *y)
	}
	if y := effectiveYear(nil, map[string]any{"year": float64(-3)}, nil); y != nil {
		t.Errorf("negative year = %v, want nil", *y)
	}
	if y := effectiveYear(zero, zero, &ten); y == nil || *y != 2010 {
		t.Errorf("zero overrides fall through to column: got %v, want 2010", y)
	}
	if y := effectiveYear(zero, map[string]any{"year": float64(1999)}, nil); y == nil || *y != 1999 {
		t.Errorf("zero override must not mask provider 1999: got %v", y)
	}
}
