// An Enter keypress that confirms an IME candidate must not also submit the
// field (ARGY-326). Browsers differ on how they flag it: `isComposing` is true
// for the keydown that commits the candidate in Chromium, while Firefox fires
// that keydown after compositionend (isComposing already false) but still
// reports the legacy keyCode 229. Checking both covers Firefox and Chromium.
export function enterCommits(e: Pick<KeyboardEvent, 'isComposing' | 'keyCode'>): boolean {
  return !e.isComposing && e.keyCode !== 229
}
