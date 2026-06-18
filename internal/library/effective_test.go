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
