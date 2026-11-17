import { describe, expect, test } from 'bun:test'
import { seasonCountLabel, yearLabel } from '../src/lib/format'

describe('yearLabel (ARGY-309)', () => {
  test('unknown years are null, never "0"', () => {
    expect(yearLabel(null)).toBeNull()
    expect(yearLabel(undefined)).toBeNull()
    expect(yearLabel(0)).toBeNull()
    expect(yearLabel(-1)).toBeNull()
    expect(yearLabel(2024)).toBe('2024')
  })
  test('season count pluralises', () => {
    expect(seasonCountLabel(1)).toBe('1 season')
    expect(seasonCountLabel(3)).toBe('3 seasons')
  })
})
