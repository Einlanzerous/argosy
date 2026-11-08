// writeGate decides whether a progress write may reach the server's stored place
// or must degrade to a keepalive (ARGY-295, subtask of ARGY-288). A keepalive
// keeps the transcode session alive but stores nothing (ARGY-289), so a stale
// local position can never overwrite a place another device has moved.
//
// Two rules:
//  - placeHold: while set, every write is a keepalive. Nothing sets it yet; the
//    place check (ARGY-296/297) raises it when another device has moved the place
//    and lowers it when the user chooses.
//  - unmount: a paused player whose position has not advanced since the last
//    accepted write has nothing new to say, so leaving it must not write. A
//    playing player still writes its final position.

export type StoredPlace = { positionSeconds: number; updatedAt?: string | null }

// Positions closer than this count as "has not advanced".
export const UNCHANGED_EPSILON_S = 1

export class WriteGate {
  placeHold = false
  // Position (seconds) and server updatedAt of the latest write the server
  // accepted from us; the updatedAt is our own echo, so a later foreign write is
  // distinguishable from it.
  lastAcceptedPosition: number | null = null
  lastAcceptedAt: string | null = null

  // seed records the place the server held when the page loaded.
  seed(state: StoredPlace | null | undefined): void {
    if (!state) return
    this.lastAcceptedPosition = state.positionSeconds
    this.lastAcceptedAt = state.updatedAt ?? null
  }

  // accept records a write the server stored (the PUT's returned PlayState).
  accept(position: number, state: StoredPlace | null | undefined): void {
    this.lastAcceptedPosition = position
    if (state?.updatedAt) this.lastAcceptedAt = state.updatedAt
  }

  // keepaliveFor returns true when a write at `position` must be a keepalive.
  // `unmount` applies the leaving-the-page rule on top of the hold.
  keepaliveFor(position: number, opts: { paused: boolean; unmount?: boolean }): boolean {
    if (this.placeHold) return true
    if (opts.unmount && opts.paused) {
      const last = this.lastAcceptedPosition
      return last === null || Math.abs(position - last) < UNCHANGED_EPSILON_S
    }
    return false
  }

  // mayMarkWatched is false while the hold is set: `ended` must not flip the
  // old item to watched over another device's place.
  mayMarkWatched(): boolean {
    return !this.placeHold
  }
}
