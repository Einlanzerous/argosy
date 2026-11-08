import { describe, expect, test } from 'bun:test'
import { WriteGate } from '../src/lib/writeGate'

// ARGY-295: the gate that keeps a stale local position from ever being stored.

describe('WriteGate', () => {
  test('without a hold, an ordinary write is not a keepalive', () => {
    const g = new WriteGate()
    expect(g.keepaliveFor(120, { paused: false })).toBe(false)
    expect(g.keepaliveFor(120, { paused: true })).toBe(false)
    expect(g.mayMarkWatched()).toBe(true)
  })

  test('placeHold forces keepalive for pause, seeked, heartbeat and unmount alike', () => {
    const g = new WriteGate()
    g.placeHold = true
    expect(g.keepaliveFor(120, { paused: true })).toBe(true) // pause / seeked
    expect(g.keepaliveFor(120, { paused: false })).toBe(true) // playing heartbeat
    expect(g.keepaliveFor(120, { paused: false, unmount: true })).toBe(true) // even a playing unmount
    expect(g.mayMarkWatched()).toBe(false) // ended
  })

  test('releasing the hold restores normal writes', () => {
    const g = new WriteGate()
    g.placeHold = true
    g.placeHold = false
    expect(g.keepaliveFor(120, { paused: false })).toBe(false)
    expect(g.mayMarkWatched()).toBe(true)
  })

  test('unmount on a paused player unchanged since the last accepted write is a keepalive', () => {
    const g = new WriteGate()
    g.accept(300, { positionSeconds: 300, updatedAt: 't1' })
    expect(g.keepaliveFor(300, { paused: true, unmount: true })).toBe(true)
    expect(g.keepaliveFor(300.4, { paused: true, unmount: true })).toBe(true)
  })

  test('unmount on a paused player that advanced still writes', () => {
    const g = new WriteGate()
    g.accept(300, { positionSeconds: 300, updatedAt: 't1' })
    expect(g.keepaliveFor(340, { paused: true, unmount: true })).toBe(false)
  })

  test('a playing player still writes its final position on unmount', () => {
    const g = new WriteGate()
    g.accept(300, { positionSeconds: 300, updatedAt: 't1' })
    expect(g.keepaliveFor(300, { paused: false, unmount: true })).toBe(false)
    expect(g.keepaliveFor(450, { paused: false, unmount: true })).toBe(false)
  })

  test('with no accepted write known, a paused unmount does not write', () => {
    expect(new WriteGate().keepaliveFor(300, { paused: true, unmount: true })).toBe(true)
  })

  test('seed takes the place the server held at load', () => {
    const g = new WriteGate()
    g.seed({ positionSeconds: 600, updatedAt: 't0' })
    expect(g.keepaliveFor(600, { paused: true, unmount: true })).toBe(true)
    expect(g.lastAcceptedAt).toBe('t0')
  })

  test('accept keeps the latest returned updatedAt as our own echo', () => {
    const g = new WriteGate()
    g.accept(10, { positionSeconds: 10, updatedAt: 't1' })
    g.accept(20, { positionSeconds: 20, updatedAt: 't2' })
    g.accept(30, null)
    expect(g.lastAcceptedAt).toBe('t2')
    expect(g.lastAcceptedPosition).toBe(30)
  })
})
