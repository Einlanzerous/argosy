// Splits WebVTT text into cue blocks, each already broken into lines and paired
// with the index of its "-->" timing line (-1 for a header or note block). Left
// to the caller to decide whether to strip CRs first — shiftVtt must not.
function vttBlocks(text: string): { lines: string[]; tIdx: number }[] {
  return text.split(/\n[ \t]*\n/).map((block) => {
    const lines = block.split('\n')
    return { lines, tIdx: lines.findIndex((l) => l.includes('-->')) }
  })
}

// WebVTT cue timestamps are in absolute media time. Under a server-side
// transcode seek the HLS timeline restarts at `baseOffset`, so the <video>'s
// currentTime is relative to that offset. shiftVtt rewrites the cue timings by
// `deltaSeconds` (use -baseOffset) so cues line up with the relative timeline;
// cues that end before zero are dropped. Direct play passes delta 0 (no-op).
export function shiftVtt(text: string, deltaSeconds: number): string {
  if (!deltaSeconds) return text
  const out: string[] = []
  // Not CR-stripped: shiftVtt rewrites timings in place and hands the rest of
  // the document back byte-for-byte.
  for (const { lines, tIdx } of vttBlocks(text)) {
    if (tIdx === -1) {
      out.push(lines.join('\n')) // header or note block — leave untouched
      continue
    }
    const shifted = shiftTimingLine(lines[tIdx], deltaSeconds)
    if (!shifted) continue // cue fell entirely before the seek point
    lines[tIdx] = shifted
    out.push(lines.join('\n'))
  }
  return out.join('\n\n')
}

// shiftTimingLine shifts the two timestamps on a cue timing line, preserving any
// trailing cue settings. Returns null when the cue ends at/under zero.
function shiftTimingLine(line: string, delta: number): string | null {
  const [left, right] = line.split('-->')
  if (right === undefined) return line
  const rightParts = right.trim().split(/\s+/)
  const start = parseTs(left.trim()) + delta
  const end = parseTs(rightParts[0]) + delta
  if (end <= 0) return null
  const settings = rightParts.slice(1).join(' ')
  const head = `${formatTs(Math.max(0, start))} --> ${formatTs(end)}`
  return settings ? `${head} ${settings}` : head
}

export interface VttCue {
  start: number
  end: number
  text: string
}

// parseVttCues extracts cues from WebVTT text so we can add them directly to a
// TextTrack via the VTTCue API — more reliable than depending on the browser to
// parse a <track src> blob and fire its load event at the right time.
export function parseVttCues(text: string): VttCue[] {
  const cues: VttCue[] = []
  for (const { lines, tIdx } of vttBlocks(text.replace(/\r/g, ''))) {
    if (tIdx === -1) continue // header or note block
    const [left, right] = lines[tIdx].split('-->')
    if (right === undefined) continue
    const start = parseTs(left.trim())
    const end = parseTs(right.trim().split(/\s+/)[0])
    if (!(end > start)) continue
    const body = lines
      .slice(tIdx + 1)
      .join('\n')
      .trim()
    if (body) cues.push({ start, end, text: body })
  }
  return cues
}

// parseTs reads HH:MM:SS.mmm or MM:SS.mmm into seconds.
function parseTs(ts: string): number {
  const [hms, ms = '0'] = ts.split('.')
  const parts = hms.split(':').map(Number)
  let sec = 0
  for (const p of parts) sec = sec * 60 + p
  return sec + Number(ms.padEnd(3, '0')) / 1000
}

function formatTs(seconds: number): string {
  const ms = Math.round((seconds - Math.floor(seconds)) * 1000)
  let s = Math.floor(seconds)
  const h = Math.floor(s / 3600)
  s -= h * 3600
  const m = Math.floor(s / 60)
  s -= m * 60
  const p2 = (n: number) => String(n).padStart(2, '0')
  return `${p2(h)}:${p2(m)}:${p2(s)}.${String(ms).padStart(3, '0')}`
}
