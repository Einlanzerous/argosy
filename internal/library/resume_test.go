package library

import (
	"testing"
	"time"

	openapi_types "github.com/oapi-codegen/runtime/types"
)

func rEp(n byte, watched bool, pos float64, at time.Time) resumeEp {
	r := resumeEp{item: openapi_types.UUID{15: n}, watched: watched, position: pos}
	if !at.IsZero() {
		r.updated = &at
	}
	return r
}

// ARGY-320: Arin's Scrubs. S3E15-17 watched, S3E18 in progress (newest); S8 rows
// all bulk-unwatched at an older time, with strays at 13s (E3) and 8s (E9).
func TestSeriesResumeIgnoresBulkUnwatchStrays(t *testing.T) {
	old := time.Date(2026, 11, 1, 4, 16, 22, 0, time.UTC)
	d19 := time.Date(2026, 11, 19, 20, 0, 0, 0, time.UTC)
	d20 := time.Date(2026, 11, 20, 2, 0, 0, 0, time.UTC)
	eps := []resumeEp{
		rEp(15, true, 0, d19), rEp(16, true, 0, d19.Add(time.Hour)), rEp(17, true, 0, d19.Add(2*time.Hour)),
		rEp(18, false, 136, d20), rEp(19, false, 0, time.Time{}),
		rEp(81, false, 0, old), rEp(83, false, 13, old), rEp(89, false, 8, old),
	}
	got := seriesResume(eps)
	if got == nil || *got != eps[3].item {
		t.Fatalf("resume = %v, want S3E18 %v", got, eps[3].item)
	}
}

func TestSeriesResume(t *testing.T) {
	at := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	t.Run("nothing touched", func(t *testing.T) {
		if got := seriesResume([]resumeEp{rEp(1, false, 0, time.Time{}), rEp(2, false, 3, at)}); got != nil {
			t.Fatalf("got %v, want nil", got)
		}
	})
	t.Run("finished frontier resumes the next episode", func(t *testing.T) {
		eps := []resumeEp{rEp(1, true, 0, at), rEp(2, false, 0, time.Time{})}
		if got := seriesResume(eps); got == nil || *got != eps[1].item {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("finished last episode has nothing to resume", func(t *testing.T) {
		if got := seriesResume([]resumeEp{rEp(1, true, 0, at)}); got != nil {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("fresh start under the threshold still resumes", func(t *testing.T) {
		eps := []resumeEp{rEp(1, false, 60, at), rEp(2, false, 0, time.Time{})}
		if got := seriesResume(eps); got == nil || *got != eps[0].item {
			t.Fatalf("got %v", got)
		}
	})
	t.Run("combined rip skips its own file", func(t *testing.T) {
		a := rEp(1, true, 0, at)
		b := a // same file backs E2
		eps := []resumeEp{a, b, rEp(3, false, 0, time.Time{})}
		if got := seriesResume(eps); got == nil || *got != eps[2].item {
			t.Fatalf("got %v", got)
		}
	})
}
