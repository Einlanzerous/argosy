package subtitle

import (
	"bufio"
	"io"
	"regexp"
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

// drawingRe matches an ASS vector drawing that survived conversion as text.
// ffmpeg strips the {\p1} override that marks one but keeps the path itself,
// so a typeset sign arrives as a cue reading "m 442 308 l 1450 308 …". The
// grammar is a move command followed only by drawing commands and numbers,
// which no line of dialogue matches.
var drawingRe = regexp.MustCompile(`^m(\s+-?\d+(\.\d+)?){2}(\s+([mnlbspc]|-?\d+(\.\d+)?))*$`)

// RepairVTT rewrites ffmpeg's WebVTT output into something every client can
// parse (ARGY-286). Two things go wrong with typeset ASS input:
//
//   - An ASS paragraph break (\N\N) becomes a blank line inside one cue. In
//     WebVTT a blank line ends a cue, so the rest of the event turns into a
//     block with no timing line. Browsers drop it, silently losing the text;
//     the mobile client's parser throws on it and loses the whole track.
//     Such a block is joined back onto the cue it came from.
//   - A vector drawing is left behind as a cue of path commands. Those lines
//     are dropped, and a cue left with no text goes with them.
//
// The header, NOTE, STYLE and REGION blocks pass through untouched.
func RepairVTT(r io.Reader, w io.Writer) error {
	raw, err := io.ReadAll(r)
	if err != nil {
		return err
	}
	text := strings.ReplaceAll(string(raw), "\r\n", "\n")

	var blocks [][]string // each block is its lines; cue blocks keep timing first
	for _, b := range splitBlocks(text) {
		lines := strings.Split(b, "\n")
		switch {
		case len(blocks) == 0, isMetaBlock(lines[0]), hasTiming(lines):
			blocks = append(blocks, lines)
		case hasTiming(blocks[len(blocks)-1]):
			// An orphan: the tail of the previous cue, split off by a blank line.
			prev := &blocks[len(blocks)-1]
			*prev = append(*prev, lines...)
		default:
			// Text before the first cue (or after a NOTE) belongs to no cue, and
			// nothing can be timed against it. WebVTT ignores it; so do we.
		}
	}

	bw := bufio.NewWriter(w)
	first := true
	for _, lines := range blocks {
		if hasTiming(lines) {
			lines = dropDrawings(lines)
			if lines == nil {
				continue
			}
		}
		if !first {
			if _, err := bw.WriteString("\n"); err != nil {
				return err
			}
		}
		first = false
		if _, err := bw.WriteString(strings.Join(lines, "\n") + "\n"); err != nil {
			return err
		}
	}
	return bw.Flush()
}

// blankLineRe is a WebVTT block separator: a line holding nothing but spaces.
var blankLineRe = regexp.MustCompile(`\n[ \t]*\n`)

// splitBlocks splits WebVTT text on blank lines, dropping empty blocks.
func splitBlocks(text string) []string {
	var out []string
	for _, b := range blankLineRe.Split(text, -1) {
		if b = strings.Trim(b, "\n"); strings.TrimSpace(b) != "" {
			out = append(out, b)
		}
	}
	return out
}

func hasTiming(lines []string) bool {
	// A cue's timing line is its first line, or its second after an identifier.
	for i := 0; i < len(lines) && i < 2; i++ {
		if strings.Contains(lines[i], "-->") {
			return true
		}
	}
	return false
}

func isMetaBlock(first string) bool {
	for _, p := range []string{"WEBVTT", "NOTE", "STYLE", "REGION"} {
		if first == p || strings.HasPrefix(first, p+" ") || strings.HasPrefix(first, p+"\t") {
			return true
		}
	}
	return false
}

// dropDrawings removes drawing-command lines from a cue's text. It returns nil
// when no text is left, so the caller drops the cue.
func dropDrawings(lines []string) []string {
	t := 0
	for t < len(lines) && !strings.Contains(lines[t], "-->") {
		t++
	}
	head, kept := lines[:t+1], []string{}
	for _, l := range lines[t+1:] {
		if !drawingRe.MatchString(strings.TrimSpace(l)) {
			kept = append(kept, l)
		}
	}
	if len(kept) == 0 {
		return nil
	}
	return append(append([]string{}, head...), kept...)
}
