// Runtime like "2h 04m" / "47m" from a duration in seconds.
export function formatRuntime(seconds: number | null | undefined): string {
  if (!seconds || seconds <= 0) return '—'
  const total = Math.round(seconds / 60)
  const h = Math.floor(total / 60)
  const m = total % 60
  if (h === 0) return `${m}m`
  return `${h}h ${String(m).padStart(2, '0')}m`
}

// Coarse relative time like "just now" / "3h ago" / "2d ago" from an ISO date.
export function formatRelative(iso: string | null | undefined): string {
  if (!iso) return 'never'
  const then = new Date(iso).getTime()
  if (Number.isNaN(then)) return 'unknown'
  const secs = Math.max(0, Math.round((Date.now() - then) / 1000))
  if (secs < 60) return 'just now'
  const mins = Math.round(secs / 60)
  if (mins < 60) return `${mins}m ago`
  const hours = Math.round(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.round(hours / 24)
  return `${days}d ago`
}

// Humanize an episode-code title: replaces a "S01E02" / "s1e2" token with
// "Season 1 Ep 2" so cryptic codes don't leak into the UI. Leaves the rest of
// the title (show name, real episode title) intact, and titles without a code
// untouched. Examples:
//   "The Good Place s01e01"        → "The Good Place · Season 1 Ep 1"
//   "Sword Art Online S01E02 Sword"→ "Sword Art Online · Season 1 Ep 2 Sword"
const episodeCode = /\s*[·\-—]?\s*S(\d{1,2})E(\d{1,2})\b/i

export function formatTitle(title: string | null | undefined): string {
  if (!title) return ''
  const m = title.match(episodeCode)
  if (!m) return title
  const human = `Season ${Number(m[1])} Ep ${Number(m[2])}`
  const replaced = title.replace(episodeCode, ` · ${human}`)
  // Collapse a leading separator if the code was at the very start.
  return replaced.replace(/^\s*·\s*/, '').trim()
}

// A real episode name, or null when the title is still the "<Show> S01E01"
// filename fallback (carries an SxxExx code). Lets callers show a name only once
// TMDB per-episode metadata (ARGY-58) has landed. Mirrored in mobile format.dart.
const hasEpisodeCode = /S\d{1,2}E\d{1,2}/i
export function episodeName(title: string | null | undefined): string | null {
  if (!title) return null
  if (hasEpisodeCode.test(title)) return null
  return title
}

// Now-playing header for a series episode: "Show · Episode Title · Season 1, Ep 1".
// episodeTitle is dropped when absent (films, or episodes without a resolved name).
// Mirrored in mobile format.dart.
export function episodeHeader(
  seriesTitle: string,
  episodeTitle: string | null | undefined,
  seasonNumber: number,
  episodeNumber: number,
): string {
  const parts = [seriesTitle]
  if (episodeTitle) parts.push(episodeTitle)
  parts.push(`Season ${seasonNumber}, Ep ${episodeNumber}`)
  return parts.join(' · ')
}

// Clock like "0:42:15" from a position in seconds.
export function formatClock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  return `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
}
