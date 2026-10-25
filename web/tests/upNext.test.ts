import { describe, expect, test } from 'bun:test'
import { SeekHold, UP_NEXT_ARM_SECONDS, isRealEnd } from '../src/lib/upNext'

// Advances the playhead from `from` by `seconds`, a timeupdate every 0.25s, and
// returns the final position.
function play(h: SeekHold, from: number, seconds: number): number {
  let pos = from
  h.noteProgress(pos) // the first tick after a seek only anchors the playhead
  for (let t = 0; t < seconds; t += 0.25) {
    pos += 0.25
    h.noteProgress(pos)
  }
  return pos
}

describe('SeekHold (ARGY-261)', () => {
  test('reaching the window by playing is never held', () => {
    const h = new SeekHold()
    expect(h.held).toBe(false)
    play(h, 1300, 20)
    expect(h.held).toBe(false)
  })

  test('a seek holds until N seconds have played', () => {
    const h = new SeekHold()
    h.noteSeek()
    expect(h.held).toBe(true)
    const pos = play(h, 1400, UP_NEXT_ARM_SECONDS - 1)
    expect(h.held).toBe(true)
    play(h, pos, 1.25)
    expect(h.held).toBe(false)
  })

  test('the call that lifts the hold says so, once', () => {
    const h = new SeekHold()
    h.noteSeek()
    let lifted = 0
    let pos = 1400
    h.noteProgress(pos)
    for (let i = 0; i < 40; i++) {
      pos += 0.25
      if (h.noteProgress(pos)) lifted++
    }
    expect(lifted).toBe(1)
  })

  test('a second seek re-holds', () => {
    const h = new SeekHold()
    h.noteSeek()
    play(h, 1400, UP_NEXT_ARM_SECONDS)
    expect(h.held).toBe(false)
    h.noteSeek()
    expect(h.held).toBe(true)
    play(h, 1420, 2)
    expect(h.held).toBe(true)
  })

  test('a paused player (no movement) accrues nothing', () => {
    const h = new SeekHold()
    h.noteSeek()
    for (let i = 0; i < 100; i++) h.noteProgress(1400)
    expect(h.held).toBe(true)
  })

  test('an end within a second of the duration is real, held or not', () => {
    const h = new SeekHold()
    h.noteSeek()
    expect(h.held).toBe(true)
    expect(isRealEnd(1440, 1440)).toBe(true)
    expect(isRealEnd(1439.5, 1440)).toBe(true)
    // Far from the end, with nothing played since the seek, it is a seek's echo.
    expect(isRealEnd(1410, 1440)).toBe(false)
    expect(isRealEnd(0, 0)).toBe(false)
  })

  test('a jump is a seek, not playing', () => {
    const h = new SeekHold()
    h.noteSeek()
    h.noteProgress(1400)
    h.noteProgress(1420)
    h.noteProgress(1380)
    expect(h.held).toBe(true)
  })
})
