// Fullscreen target selection for the web player (ARGY-287).
//
// App.vue keys the player route by fullPath, so every episode change unmounts
// PlayerView and its `.player` element. A fullscreen element that leaves the DOM
// ends fullscreen, and a fresh requestFullscreen() needs a user gesture that an
// ended-driven auto-advance does not have. So fullscreen is held by a stable
// wrapper in App.vue (`FULLSCREEN_ROOT_ATTR`) that outlives the swap.

export const FULLSCREEN_ROOT_ATTR = 'data-fullscreen-root'
const ROOT_SELECTOR = `[${FULLSCREEN_ROOT_ATTR}]`

interface Closest<T> {
  closest(selector: string): T | null
}

// The element to fullscreen for a given video: the stable root when there is
// one, else the player itself (so a PlayerView mounted outside App.vue still
// works, just without surviving a remount).
export function fullscreenTarget<T>(video: Closest<T> | null | undefined): T | null {
  if (!video) return null
  return video.closest(ROOT_SELECTOR) ?? video.closest('.player')
}

// Whether a route change should end fullscreen: the stable root outlives the
// player, so leaving the player route has to exit explicitly or the next page
// would render fullscreen. Player-to-player (auto-advance) keeps it.
export function shouldExitFullscreen<T>(
  routeName: unknown,
  fullscreenElement: T | null,
  root: T | null,
): boolean {
  return routeName !== 'player' && root !== null && fullscreenElement === root
}
