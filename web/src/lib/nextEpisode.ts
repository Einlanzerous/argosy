// The next-episode lookup behind auto-advance (ARGY-264).
//
// It used to be a single request at mount whose failure read as "last episode",
// so one blip (a deploy, a dropped link, an edge ban) disabled Up Next for the
// whole episode. Only a server answer is terminal now: an episode, or null for
// "nothing follows". A failure stays retryable, on the signals that say the
// server is reachable again, within a bound so a dead link can't become a storm.
// Mirrors the mobile controller's `_loadNextEpisode`.

export const NEXT_EPISODE_MAX_ATTEMPTS = 3
export const NEXT_EPISODE_RETRY_GAP_MS = 10_000

type State = 'unfetched' | 'fetched' | 'failed'

export interface NextEpisodeOptions<T> {
  /** Resolves null when nothing follows; rejects when the answer is unknown. */
  fetch: () => Promise<T | null>
  /** Called with the answer when the server gives one. */
  onResolved: (value: T | null) => void
  now?: () => number
  maxAttempts?: number
  gapMs?: number
  onFailure?: (err: unknown) => void
}

export class NextEpisodeLookup<T> {
  private state: State = 'unfetched'
  private inFlight: Promise<void> | null = null
  private lastAt: number | null = null
  private finalTried = false
  attempts = 0

  constructor(private readonly o: NextEpisodeOptions<T>) {}

  get failed(): boolean {
    return this.state === 'failed'
  }

  /**
   * Asks, unless it is already answered, already in flight, too soon after the
   * last attempt, or out of attempts. `last` is the end-of-file attempt: it
   * skips the spacing and the cap once, because the alternative is stranding the
   * viewer on a finished frame.
   */
  load(last = false): Promise<void> {
    if (this.state === 'fetched') return Promise.resolve()
    if (this.inFlight) return this.inFlight
    const now = (this.o.now ?? Date.now)()
    if (last) {
      if (this.finalTried) return Promise.resolve()
      this.finalTried = true
    } else {
      if (this.attempts >= (this.o.maxAttempts ?? NEXT_EPISODE_MAX_ATTEMPTS)) {
        return Promise.resolve()
      }
      if (this.lastAt !== null && now - this.lastAt < (this.o.gapMs ?? NEXT_EPISODE_RETRY_GAP_MS)) {
        return Promise.resolve()
      }
    }
    this.attempts++
    this.lastAt = now
    this.inFlight = this.o
      .fetch()
      .then(
        (v) => {
          this.state = 'fetched'
          this.o.onResolved(v)
        },
        (err) => {
          this.state = 'failed'
          if (this.attempts === 1) this.o.onFailure?.(err)
        },
      )
      .finally(() => {
        this.inFlight = null
      })
    return this.inFlight
  }
}
