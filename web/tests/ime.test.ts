import { describe, expect, test } from 'bun:test'
import { enterCommits } from '../src/lib/ime'

describe('enterCommits', () => {
  test('a plain Enter submits', () => {
    expect(enterCommits({ isComposing: false, keyCode: 13 })).toBe(true)
  })

  test('Enter that confirms an IME candidate (isComposing) does not submit', () => {
    expect(enterCommits({ isComposing: true, keyCode: 13 })).toBe(false)
  })

  test('Firefox reports the committing keydown as keyCode 229 after compositionend', () => {
    expect(enterCommits({ isComposing: false, keyCode: 229 })).toBe(false)
  })
})
