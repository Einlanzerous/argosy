package subtitle

import (
	"bufio"
	"io"
	"strings"
)

// SRTToVTT converts SubRip (SRT) subtitle data into WebVTT, the format an HTML5
// <track> element understands. The transformation is small: a "WEBVTT" header,
// comma→period in cue timestamps (00:00:01,000 → 00:00:01.000), and CRLF/BOM
// normalization. Inline tags (<i>, <b>) are already valid in both formats.
func SRTToVTT(r io.Reader, w io.Writer) error {
	bw := bufio.NewWriter(w)
	if _, err := bw.WriteString("WEBVTT\n\n"); err != nil {
		return err
	}

	sc := bufio.NewScanner(r)
	// Subtitle cues are short, but allow generous lines so an over-long entry
	// can't truncate mid-cue.
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	first := true
	for sc.Scan() {
		line := sc.Text()
		if first {
			line = strings.TrimPrefix(line, "\ufeff") // strip UTF-8 BOM
			first = false
		}
		line = strings.TrimSuffix(line, "\r")
		// Cue timing lines carry the only commas that must become periods.
		if strings.Contains(line, "-->") {
			line = strings.ReplaceAll(line, ",", ".")
		}
		if _, err := bw.WriteString(line); err != nil {
			return err
		}
		if err := bw.WriteByte('\n'); err != nil {
			return err
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return bw.Flush()
}
