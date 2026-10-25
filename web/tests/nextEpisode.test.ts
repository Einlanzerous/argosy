import { describe, expect, test } from 'bun:test'
import { NextEpisodeLookup } from '../src/lib/nextEpisode'

// Builds a lookup whose fetch plays back `outcomes` (an Error fails, anything
// else is the server's answer), on a manual clock.
function rig(outcomes: Array<Error | string | null>) {
  const clock = { t: 0 }
  const got: Array<string | null> = []
  let calls = 0
  const lookup = new NextEpisodeLookup<string>({
    fetch: async () => {
      const o = outcomes[Math.min(calls, outcomes.length - 1)]
      calls++
      if (o instanceof Error) throw o
      return o
    },
    onResolved: (v) => got.push(v),
    now: () => clock.t,
  })
  return { lookup, clock, got, calls: () => calls }
}

describe('NextEpisodeLookup (ARGY-264)', () => {
  test('a failure is retryable and a later success resolves', async () => {
    const r = rig([new Error('down'), 'next'])
    await r.lookup.load()
    expect(r.lookup.failed).toBe(true)
    expect(r.got).toEqual([])

    r.clock.t = 11_000
    await r.lookup.load()
    expect(r.got).toEqual(['next'])
    expect(r.lookup.failed).toBe(false)
  })

  test('retries are spaced', async () => {
    const r = rig([new Error('down')])
    await r.lookup.load()
    r.clock.t = 5_000
    await r.lookup.load()
    expect(r.calls()).toBe(1)
    r.clock.t = 10_000
    await r.lookup.load()
    expect(r.calls()).toBe(2)
  })

  test('concurrent loads are one request', async () => {
    const r = rig([new Error('down')])
    await Promise.all([r.lookup.load(), r.lookup.load(), r.lookup.load()])
    expect(r.calls()).toBe(1)
  })

  test('a lookup that keeps failing is bounded; the end of file gets one more', async () => {
    const r = rig([new Error('down')])
    for (let i = 0; i < 20; i++) {
      r.clock.t += 11_000
      await r.lookup.load()
    }
    expect(r.calls()).toBe(3)
    await r.lookup.load(true)
    expect(r.calls()).toBe(4)
    await r.lookup.load(true)
    expect(r.calls()).toBe(4)
  })

  test('an answer of "nothing follows" is terminal', async () => {
    const r = rig([null])
    await r.lookup.load()
    expect(r.got).toEqual([null])
    expect(r.lookup.failed).toBe(false)
    r.clock.t = 100_000
    await r.lookup.load()
    await r.lookup.load(true)
    expect(r.calls()).toBe(1)
  })
})
