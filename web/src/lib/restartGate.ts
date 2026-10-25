// The transcode restart, serialised behind a generation (ARGY-260).
//
// A restart is: stop the old session, POST a new one, poll its playlist, attach
// it. Every one of those is an await, and a second seek landing in any of them
// used to run a second restart alongside the first — one killed the other's
// session and reported a bogus "transcoder" error, or both POSTed and the loser
// attached last over the winner, leaking the winner's session. ARGY-220
// serialised stop-before-POST *within* one restart; this serialises *across*
// them: each restart takes the next generation, re-checks it after every await,
// and a superseded one bails silently. The newest seek always wins and a
// superseded restart is not a failure, so it never reports an error, never
// touches the player, and never clears `starting` for the one still live.

export interface RestartSession {
  id: string
  playlistUrl: string
}

export interface RestartContext {
  /** True once a newer restart (or a cancel) has taken over. */
  isStale(): boolean
  /** Moves the committed offset to the one this restart is headed for. */
  commit(): void
}

export interface RestartDeps<S extends RestartSession> {
  getSessionId(): string
  setSessionId(id: string): void
  /** Synchronous setup: tear the old player source down, show the spinner. */
  begin(offset: number): void
  stop(id: string): Promise<void>
  start(offset: number): Promise<S | null>
  probe(url: string, cancelled: () => boolean): Promise<boolean>
  /**
   * Brings the new source up. Returns true when it will call `ctx.commit()`
   * itself once the source is actually attached; false means commit now.
   */
  attach(session: S, ctx: RestartContext): boolean
  /** The new source is up: the offset its clock is measured from. */
  commit(offset: number): void
  /** Only ever called for the winning generation. */
  fail(reason: 'start' | 'slow' | 'play'): void
  /** Only ever called for the winning generation, after success or failure. */
  settle(): void
}

export class RestartGate {
  private gen = 0
  private pendingOffset: number | null = null
  private pendingStop: Promise<void> | null = null
  private readonly stopping = new Set<string>()
  private committedOffset = 0

  /** The target of the restart in flight, or null. Position reads use it. */
  get pending(): number | null {
    return this.pendingOffset
  }

  get inFlight(): boolean {
    return this.pendingOffset !== null
  }

  /** Supersedes anything in flight without starting something new. */
  cancel(): void {
    this.gen++
    this.pendingOffset = null
  }

  /** The offset the last winning restart committed. */
  get offset(): number {
    return this.committedOffset
  }

  async run<S extends RestartSession>(offset: number, d: RestartDeps<S>): Promise<void> {
    const gen = ++this.gen
    const stale = () => gen !== this.gen
    const old = d.getSessionId()
    d.setSessionId('')
    this.pendingOffset = offset
    const commit = () => {
      if (stale() || this.pendingOffset === null) return
      this.committedOffset = this.pendingOffset
      this.pendingOffset = null
      d.commit(this.committedOffset)
    }
    let attached = false
    d.begin(offset)
    try {
      if (old) {
        this.stopping.add(old)
        // Chained, so a restart that finds no session id (the one before it
        // already took it) still waits for that stop before POSTing: ids are
        // deterministic in the floor of startAt and the server joins a live
        // session with a matching id (ARGY-220).
        const prev = this.pendingStop
        this.pendingStop = (async () => {
          if (prev) await prev
          await d.stop(old).catch(() => {})
        })()
      }
      if (this.pendingStop) await this.pendingStop
      if (stale()) return
      const sess = await d.start(offset).catch(() => null)
      if (stale()) {
        if (sess) this.discard(sess.id, offset, d)
        return
      }
      if (!sess) {
        d.fail('start')
        return
      }
      d.setSessionId(sess.id)
      const ready = await d.probe(sess.playlistUrl, stale)
      if (stale()) {
        this.discard(sess.id, offset, d)
        return
      }
      if (!ready) {
        d.fail('slow')
        return
      }
      attached = d.attach(sess, { isStale: stale, commit })
      if (!attached) commit()
    } catch {
      if (!stale()) d.fail('play')
    } finally {
      if (!stale()) {
        // A failure never reached the point of committing; land on the target
        // so a retry restarts where the viewer asked to be.
        if (!attached) commit()
        d.settle()
      }
    }
  }

  // Stops a session a superseded restart brought up, unless a newer one is using
  // it: ids are deterministic in the floor of startAt, so a stop here could kill
  // the winner's session.
  private discard(
    id: string,
    offset: number,
    d: Pick<RestartDeps<RestartSession>, 'getSessionId' | 'stop'>,
  ): void {
    const sameSecond =
      this.pendingOffset !== null && Math.floor(this.pendingOffset) === Math.floor(offset)
    if (this.stopping.has(id) || d.getSessionId() === id || sameSecond) return
    void d.stop(id).catch(() => {})
  }
}
