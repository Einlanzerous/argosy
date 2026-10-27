package library

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"slices"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/transcode"
)

// hevc4KFixture is an 8-bit 4K HEVC source with one audio track. With hevc=false
// it re-encodes to the H.264 ladder (1080/720/480); with hevc=true it copies.
// That split is what makes both the hints and a zeroed hevc observable on the
// Spec that reaches the transcoder.
const hevc4KFixture = `{"streams":[
	{"index":0,"codec_type":"video","codec_name":"hevc","height":2160,"pix_fmt":"yuv420p"},
	{"index":1,"codec_type":"audio","codec_name":"aac","tags":{"language":"eng"}}
]}`

// TestStartTranscodeRefusesMalformedHints: a present hint that is not a positive
// integer is a client bug and is refused, not read as absent (ARGY-179). Nothing
// is started for a refused body.
func TestStartTranscodeRefusesMalformedHints(t *testing.T) {
	h, be, itemID := transcodeFixture(t, hevc4KFixture)

	for _, body := range []string{
		`{"minHeight":0}`,
		`{"maxHeight":0}`,
		`{"minHeight":-1}`,
		`{"maxHeight":-1080}`,
		`{"minHeight":"abc"}`,
		`{"maxHeight":"1080"}`,
		`{"minHeight":1080.5}`,
		`{"minHeight":true}`,
		`{"minHeight":[1080]}`,
		// Go reports only the first type error — on hevc here — and leaves
		// minHeight allocated to 0, so the "<= 0" rule has to catch it.
		`{"hevc":"yes","minHeight":"abc"}`,
	} {
		rec := postTranscode(t, h, itemID, body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400 (body %s)", body, rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "positive integer") {
			t.Errorf("%s: error %q should name the rule", body, rec.Body.String())
		}
	}
	be.mu.Lock()
	started := len(be.specs)
	be.mu.Unlock()
	if started != 0 {
		t.Errorf("%d sessions started for refused bodies; want none", started)
	}
}

// TestStartTranscodeRefusesInvertedHints: minHeight > maxHeight as sent is a
// 400 — including on a source the planner would copy, because the check runs
// before the method decision.
func TestStartTranscodeRefusesInvertedHints(t *testing.T) {
	h, be, itemID := transcodeFixture(t, hevc4KFixture)

	for _, body := range []string{
		`{"minHeight":1080,"maxHeight":720}`,
		// hevc=true copies this source; the inconsistency is still refused.
		`{"hevc":true,"minHeight":2160,"maxHeight":1080}`,
	} {
		rec := postTranscode(t, h, itemID, body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400 (body %s)", body, rec.Code, rec.Body.String())
		}
	}
	be.mu.Lock()
	started := len(be.specs)
	be.mu.Unlock()
	if started != 0 {
		t.Errorf("%d sessions started for inverted hints; want none", started)
	}
}

// TestStartTranscodeHonoursHints: either hint alone or both reach the Spec and
// shape the planned ladder; a hint that is JSON null reads as absent.
func TestStartTranscodeHonoursHints(t *testing.T) {
	for _, tc := range []struct {
		name       string
		body       string
		minH, maxH int
		rungs      []int
	}{
		{"both hints", `{"minHeight":2160,"maxHeight":2160}`, 2160, 2160, []int{1080}},
		{"minHeight alone", `{"minHeight":1080}`, 1080, 0, []int{1080}},
		{"maxHeight alone", `{"maxHeight":720}`, 0, 720, []int{720, 480}},
		{"equal on a rung", `{"minHeight":720,"maxHeight":720}`, 720, 720, []int{720}},
		{"the phone's body: nulls", `{"minHeight":null,"maxHeight":null}`, 0, 0, []int{1080, 720, 480}},
		{"startAt alongside", `{"startAt":42,"hevc":false,"maxHeight":1080}`, 0, 1080, []int{1080, 720, 480}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h, be, itemID := transcodeFixture(t, hevc4KFixture)
			rec := postTranscode(t, h, itemID, tc.body)
			if rec.Code != http.StatusAccepted {
				t.Fatalf("status = %d, want 202 (body %s)", rec.Code, rec.Body.String())
			}
			spec := be.await(t)
			if spec.Method != transcode.MethodTranscode || spec.VideoCodec != transcode.CodecH264 {
				t.Fatalf("method/codec = %s/%s, want transcode/h264 for an HEVC source and an HEVC-less client", spec.Method, spec.VideoCodec)
			}
			if spec.MinRungHeight != tc.minH || spec.MaxRungHeight != tc.maxH {
				t.Errorf("hints on the spec = min %d max %d, want min %d max %d", spec.MinRungHeight, spec.MaxRungHeight, tc.minH, tc.maxH)
			}
			var sess struct {
				ID string `json:"id"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &sess); err != nil {
				t.Fatal(err)
			}
			got, ok := h.tc.Get(sess.ID)
			if !ok {
				t.Fatalf("session %s not live", sess.ID)
			}
			if !slices.Equal(got.Rungs, tc.rungs) {
				t.Errorf("Session.Rungs = %v, want %v", got.Rungs, tc.rungs)
			}
		})
	}
}

// TestStartTranscodeUndecodableBodyIsEmpty: an empty, non-JSON or truncated
// body decodes nothing and is today's behaviour — 200, no hints, hevc=false (the
// source is HEVC, so hevc=false shows as an H.264 re-encode rather than a copy).
// A top-level non-object is a type error with no field, which lands in the same
// place.
func TestStartTranscodeUndecodableBodyIsEmpty(t *testing.T) {
	for _, body := range []string{
		``,
		`hello`,
		`{"hevc":true,"minHeight":1080,`,
		`[1,2]`,
		`null`,
	} {
		t.Run(body, func(t *testing.T) {
			h, be, itemID := transcodeFixture(t, hevc4KFixture)
			rec := postTranscode(t, h, itemID, body)
			if rec.Code != http.StatusAccepted {
				t.Fatalf("status = %d, want 202 (body %s)", rec.Code, rec.Body.String())
			}
			spec := be.await(t)
			if spec.Method != transcode.MethodTranscode || spec.VideoCodec != transcode.CodecH264 {
				t.Errorf("method/codec = %s/%s, want transcode/h264 — hevc must read as false", spec.Method, spec.VideoCodec)
			}
			if spec.MinRungHeight != 0 || spec.MaxRungHeight != 0 {
				t.Errorf("hints = min %d max %d, want none", spec.MinRungHeight, spec.MaxRungHeight)
			}
			if spec.StartAt != 0 {
				t.Errorf("startAt = %v, want 0 — nothing from a truncated body may be kept", spec.StartAt)
			}
		})
	}
}

// TestStartTranscodeTypeErrorOnOtherFieldKeepsHints: a type error on hevc
// leaves it at its zero value (false) and the hints are honoured, as today.
func TestStartTranscodeTypeErrorOnOtherFieldKeepsHints(t *testing.T) {
	h, be, itemID := transcodeFixture(t, hevc4KFixture)
	rec := postTranscode(t, h, itemID, `{"hevc":"yes","maxHeight":1080}`)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202 (body %s)", rec.Code, rec.Body.String())
	}
	spec := be.await(t)
	if spec.VideoCodec != transcode.CodecH264 || spec.Method != transcode.MethodTranscode {
		t.Errorf("method/codec = %s/%s, want transcode/h264 — a malformed hevc reads as false", spec.Method, spec.VideoCodec)
	}
	if spec.MaxRungHeight != 1080 || spec.MinRungHeight != 0 {
		t.Errorf("hints = min %d max %d, want max 1080 honoured", spec.MinRungHeight, spec.MaxRungHeight)
	}
}

// TestStartTranscodeRemuxIgnoresHints: valid hints on a request the planner
// copies change neither the response nor the session — the hinted start joins
// the unhinted copy.
func TestStartTranscodeRemuxIgnoresHints(t *testing.T) {
	h, be, itemID := transcodeFixture(t, hevc4KFixture)

	first := postTranscode(t, h, itemID, `{"hevc":true}`)
	if first.Code != http.StatusAccepted {
		t.Fatalf("unhinted: status = %d (body %s)", first.Code, first.Body.String())
	}
	spec := be.await(t)
	if spec.Method != transcode.MethodRemux {
		t.Fatalf("method = %s, want remux for an HEVC source and an HEVC client", spec.Method)
	}
	if spec.MinRungHeight != 0 || spec.MaxRungHeight != 0 {
		t.Errorf("unhinted remux carries hints min %d max %d", spec.MinRungHeight, spec.MaxRungHeight)
	}

	second := postTranscode(t, h, itemID, `{"hevc":true,"minHeight":2160,"maxHeight":2160}`)
	if second.Code != http.StatusAccepted {
		t.Fatalf("hinted: status = %d (body %s)", second.Code, second.Body.String())
	}
	var a, b struct {
		ID     string `json:"id"`
		Method string `json:"method"`
	}
	if err := json.Unmarshal(first.Body.Bytes(), &a); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(second.Body.Bytes(), &b); err != nil {
		t.Fatal(err)
	}
	if a.ID != b.ID || a.Method != b.Method {
		t.Errorf("hinted remux = %+v, unhinted = %+v; want the same session", b, a)
	}
	be.mu.Lock()
	started := len(be.specs)
	be.mu.Unlock()
	if started != 1 {
		t.Errorf("%d encodes started, want 1 — the hinted start must join the copy", started)
	}
	sess, _ := h.tc.Get(a.ID)
	if len(sess.Rungs) != 0 {
		t.Errorf("remux Session.Rungs = %v, want empty", sess.Rungs)
	}
}

// TestDecodeTranscodeBodyTable is the DB-free view of the same rules, for the
// cases whose outcome is in the parse rather than the plan.
func TestDecodeTranscodeBodyTable(t *testing.T) {
	for _, tc := range []struct {
		body       string
		wantErr    bool
		minH, maxH int
		hevc       bool
	}{
		{body: ``},
		{body: `hello`},
		{body: `{"hevc":true,"minHeight":1080,`},
		{body: `[1,2]`},
		{body: `{"minHeight":null,"maxHeight":null}`},
		{body: `{"hevc":true}`, hevc: true},
		{body: `{"hevc":"yes","maxHeight":1080}`, maxH: 1080},
		{body: `{"hevc":"yes","minHeight":"abc"}`, wantErr: true},
		{body: `{"minHeight":"abc"}`, wantErr: true},
		{body: `{"minHeight":1080.5}`, wantErr: true},
		{body: `{"minHeight":0}`, wantErr: true},
		{body: `{"maxHeight":-1}`, wantErr: true},
		{body: `{"minHeight":1081,"maxHeight":1080}`, wantErr: true},
		{body: `{"minHeight":1080,"maxHeight":1080}`, minH: 1080, maxH: 1080},
		{body: `{"minHeight":720}`, minH: 720},
		{body: `{"maxHeight":720}`, maxH: 720},
	} {
		body, minH, maxH, errMsg := decodeTranscodeBody(strings.NewReader(tc.body))
		if (errMsg != "") != tc.wantErr {
			t.Errorf("%s: err %q, wantErr %v", tc.body, errMsg, tc.wantErr)
			continue
		}
		if tc.wantErr {
			continue
		}
		if minH != tc.minH || maxH != tc.maxH {
			t.Errorf("%s: hints = min %d max %d, want min %d max %d", tc.body, minH, maxH, tc.minH, tc.maxH)
		}
		if got := body.Hevc != nil && *body.Hevc; got != tc.hevc {
			t.Errorf("%s: hevc = %v, want %v", tc.body, got, tc.hevc)
		}
	}
}

// TestStartTranscodeRemuxLogsRawHints: dropping the hints on a remux must not
// erase them from the decision line. A TV that sent min=max=2160 for a title
// that copies has to read differently from a client that sent nothing —
// otherwise the log cannot tell a TV on a pre-hint build from one on the new
// build — so the line carries the raw values beside rungs=copy, and the
// StartRequest still carries none.
func TestStartTranscodeRemuxLogsRawHints(t *testing.T) {
	h, be, itemID := transcodeFixture(t, hevc4KFixture)
	var buf bytes.Buffer
	h.logger = slog.New(slog.NewTextHandler(&buf, nil))

	rec := postTranscode(t, h, itemID, `{"hevc":true,"minHeight":2160,"maxHeight":2160}`)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want 202 (body %s)", rec.Code, rec.Body.String())
	}
	spec := be.await(t)
	if spec.Method != transcode.MethodRemux {
		t.Fatalf("method = %s, want remux", spec.Method)
	}
	if spec.MinRungHeight != 0 || spec.MaxRungHeight != 0 {
		t.Errorf("remux StartRequest carries hints min %d max %d; want none", spec.MinRungHeight, spec.MaxRungHeight)
	}

	line := ""
	for _, l := range strings.Split(buf.String(), "\n") {
		if strings.Contains(l, "transcode decision") {
			line = l
		}
	}
	if line == "" {
		t.Fatalf("no decision line logged:\n%s", buf.String())
	}
	for _, want := range []string{"method=remux", "minHeight=2160", "maxHeight=2160", "rungs=copy"} {
		if !strings.Contains(line, want) {
			t.Errorf("decision line missing %q: %s", want, line)
		}
	}

	// And the unhinted twin of the same request reads as absent, not as the
	// same zeros a dropped hint would have left.
	buf.Reset()
	rec = postTranscode(t, h, itemID, `{"hevc":true}`)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("unhinted: status = %d (body %s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(buf.String(), "minHeight=0 maxHeight=0 rungs=copy") {
		t.Errorf("unhinted remux decision line should read minHeight=0 maxHeight=0 rungs=copy:\n%s", buf.String())
	}
}
