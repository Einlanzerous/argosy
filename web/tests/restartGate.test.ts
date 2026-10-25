import { describe, expect, test } from 'bun:test'
import { RestartGate, type RestartContext, type RestartSession } from '../src/lib/restartGate'

// Two seeks inside one transcode restart used to run two restarts side by side
// (ARGY-260). The fake server mirrors the real id rule: ids are deterministic in
// the floor of startAt, and POSTing a live id joins it.

function defer() {
  let resolve!: () => void
  const promise = new Promise<void>((r) => (resolve = r))
  return { promise, resolve }
}

const tick = async () => {
  for (let i = 0; i < 20; i++) await Promise.resolve()
}

function rig() {
  const alive = new Set<string>()
  const starts: number[] = []
  const attached: string[] = []
  const errors: string[] = []
  const probeGates = new Map<string, ReturnType<typeof defer>>()
  const settles: number[] = []
  const stopGate: { current: ReturnType<typeof defer> | null } = { current: null }
  const state = { sessionId: '', base: 0, starting: false }
  const ctxs: RestartContext[] = []
  const gate = new RestartGate()

  const deps = {
    getSessionId: () => state.sessionId,
    setSessionId: (id: string) => {
      state.sessionId = id
    },
    begin: () => {
      state.starting = true
    },
    stop: async (id: string) => {
      if (stopGate.current) await stopGate.current.promise
      alive.delete(id)
    },
    start: async (o: number): Promise<RestartSession | null> => {
      starts.push(o)
      await Promise.resolve()
      const id = `s${Math.floor(o)}`
      alive.add(id)
      return { id, playlistUrl: `/p/${id}` }
    },
    probe: async (url: string) => {
      const g = probeGates.get(url)
      if (g) await g.promise
      return true
    },
    attach: (s: RestartSession, ctx: RestartContext) => {
      attached.push(s.id)
      ctxs.push(ctx)
      return true // commits on MEDIA_ATTACHED, fired by the test
    },
    commit: (o: number) => {
      state.base = o
    },
    fail: (r: string) => errors.push(r),
    settle: () => {
      state.starting = false
      settles.push(1)
    },
  }
  const gateAll = () => {
    for (const g of probeGates.values()) g.resolve()
  }
  return { gate, deps, alive, starts, attached, errors, probeGates, stopGate, state, ctxs, settles, gateAll }
}

describe('RestartGate (ARGY-260)', () => {
  test('a second seek while the first awaits the playlist wins cleanly', async () => {
    const r = rig()
    r.probeGates.set('/p/s100', defer())
    r.probeGates.set('/p/s200', defer())
    const a = r.gate.run(100, r.deps)
    await tick()
    const b = r.gate.run(200, r.deps)
    await tick()
    r.gateAll()
    await Promise.all([a, b])
    r.ctxs.at(-1)!.commit()

    expect([...r.alive]).toEqual(['s200'])
    expect(r.attached).toEqual(['s200'])
    expect(r.state.base).toBe(200)
    expect(r.errors).toEqual([])
    expect(r.state.starting).toBe(false)
    expect(r.settles.length).toBe(1)
  })

  test('a second seek while the first awaits the stop does not leak a session', async () => {
    const r = rig()
    await r.gate.run(50, r.deps)
    r.ctxs.at(-1)!.commit()
    expect([...r.alive]).toEqual(['s50'])

    r.stopGate.current = defer()
    const a = r.gate.run(100, r.deps)
    await tick()
    const b = r.gate.run(200, r.deps)
    await tick()
    // B waits on A's DELETE rather than POSTing into it.
    expect(r.starts).toEqual([50])
    r.stopGate.current.resolve()
    await Promise.all([a, b])
    r.ctxs.at(-1)!.commit()

    expect(r.starts).toEqual([50, 200])
    expect([...r.alive]).toEqual(['s200'])
    expect(r.attached).toEqual(['s50', 's200'])
    expect(r.state.base).toBe(200)
    expect(r.errors).toEqual([])
  })

  test('a superseded restart never clears starting for the live one', async () => {
    const r = rig()
    r.probeGates.set('/p/s100', defer())
    r.probeGates.set('/p/s200', defer())
    const a = r.gate.run(100, r.deps)
    await tick()
    const b = r.gate.run(200, r.deps)
    await tick()
    r.probeGates.get('/p/s100')!.resolve()
    await a
    expect(r.state.starting).toBe(true)
    r.probeGates.get('/p/s200')!.resolve()
    await b
    expect(r.state.starting).toBe(false)
  })

  test('the offset is not committed, and pending reports the target, until the source attaches', async () => {
    const r = rig()
    await r.gate.run(600, r.deps)
    r.ctxs.at(-1)!.commit()
    expect(r.state.base).toBe(600)

    r.probeGates.set('/p/s300', defer())
    const p = r.gate.run(300, r.deps)
    await tick()
    expect(r.gate.pending).toBe(300)
    expect(r.state.base).toBe(600)
    r.gateAll()
    await p
    // Attached but MEDIA_ATTACHED has not fired yet.
    expect(r.state.base).toBe(600)
    expect(r.gate.pending).toBe(300)
    r.ctxs.at(-1)!.commit()
    expect(r.state.base).toBe(300)
    expect(r.gate.pending).toBeNull()
  })

  test('a stale source cannot commit over the winner', async () => {
    const r = rig()
    await r.gate.run(100, r.deps)
    const staleCtx = r.ctxs.at(-1)!
    await r.gate.run(200, r.deps)
    staleCtx.commit()
    expect(r.state.base).toBe(0)
    r.ctxs.at(-1)!.commit()
    expect(r.state.base).toBe(200)
  })
})
