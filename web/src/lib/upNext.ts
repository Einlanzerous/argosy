// Whether the viewer has actually watched into where they are (ARGY-261).
//
// Auto-advance is caused by playing, never by a seek. A scrub that lands in the
// credits window still opens the Up Next card (Play Next stays one tap away) but
// holds its countdown until the viewer has played forward this many seconds with
// no further seek; the same notion gates `ended`, so a seek that runs off the end
// of the file marks nothing watched and rolls nothing. Counted from the playhead,
// not the wall clock, so a paused player accrues nothing. Mirrors the mobile
// controller's `upNextArmSeconds` / `_playedSinceSeek`.

export const UP_NEXT_ARM_SECONDS = 5

// A bigger forward jump between two progress ticks is a seek or a restart, not
// playing.
const MAX_STEP_SECONDS = 3

// A `finished`/`ended` this close to the catalog duration is the media really
// ending (a seek to the very end included), whatever has played since the seek.
// Mirrors the mobile controller's `_realEndSlackSeconds` (ARGY-260).
export const REAL_END_SLACK_SECONDS = 1

export function isRealEnd(position: number, duration: number): boolean {
  return duration > 0 && duration - position < REAL_END_SLACK_SECONDS
}

export class SeekHold {
  // Infinite until the first seek: reaching the window by playing is never held.
  private played = Infinity
  private last: number | null = null

  constructor(private readonly armSeconds = UP_NEXT_ARM_SECONDS) {}

  /** The viewer moved the playhead (native seek or transcode restart). */
  noteSeek(): void {
    this.played = 0
    this.last = null
  }

  /**
   * Feeds the absolute playhead from a `timeupdate`. Returns true on the call
   * that lifts the hold.
   */
  noteProgress(position: number): boolean {
    const last = this.last
    this.last = position
    if (last === null) return false
    const d = position - last
    if (d <= 0 || d > MAX_STEP_SECONDS) return false
    const was = this.held
    this.played += d
    return was && !this.held
  }

  /** The countdown must not run: a seek landed here and nothing has played since. */
  get held(): boolean {
    return this.played < this.armSeconds
  }
}
