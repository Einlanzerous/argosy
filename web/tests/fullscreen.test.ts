import { describe, expect, test } from 'bun:test'
import { fullscreenTarget, shouldExitFullscreen } from '../src/lib/fullscreen'

const video = (found: Record<string, string>) => ({
  closest: (sel: string) => found[sel] ?? null,
})

describe('fullscreenTarget', () => {
  test('prefers the stable root over .player', () => {
    const v = video({ '[data-fullscreen-root]': 'root', '.player': 'player' })
    expect(fullscreenTarget(v)).toBe('root')
  })
  test('falls back to .player without a root', () => {
    expect(fullscreenTarget(video({ '.player': 'player' }))).toBe('player')
  })
  test('null when nothing matches or no video', () => {
    expect(fullscreenTarget(video({}))).toBeNull()
    expect(fullscreenTarget(null)).toBeNull()
  })
})

describe('shouldExitFullscreen', () => {
  test('keeps fullscreen across player to player', () => {
    expect(shouldExitFullscreen('player', 'root', 'root')).toBe(false)
  })
  test('exits when leaving the player while the root is fullscreen', () => {
    expect(shouldExitFullscreen('home', 'root', 'root')).toBe(true)
  })
  test('does nothing when something else (or nothing) is fullscreen', () => {
    expect(shouldExitFullscreen('home', 'other', 'root')).toBe(false)
    expect(shouldExitFullscreen('home', null, 'root')).toBe(false)
    expect(shouldExitFullscreen('home', null, null)).toBe(false)
  })
})
