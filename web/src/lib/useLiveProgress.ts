import { onBeforeUnmount, onMounted } from 'vue'
import { subscribeBeacon } from '@/lib/beacon'
import {
  createLiveProgress,
  type LiveProgressDeps,
  type LiveProgressOptions,
} from '@/lib/liveProgress'
import { useSessionStore } from '@/stores/session'

export { patchSeriesProgress, seriesHasItem } from '@/lib/liveProgress'

const realDeps = (): LiveProgressDeps => ({
  subscribe: subscribeBeacon,
  setTimeout: (fn, ms) => setTimeout(fn, ms),
  clearTimeout: (h) => clearTimeout(h as ReturnType<typeof setTimeout>),
  now: () => Date.now(),
  doc: typeof document === 'undefined' ? null : document,
  win: typeof window === 'undefined' ? null : window,
})

// Component wrapper: subscribes on mount, tears everything down on unmount. See
// liveProgress.ts for the behaviour.
export function useLiveProgress(opts: Omit<LiveProgressOptions, 'deviceId'>): void {
  const store = useSessionStore()
  const live = createLiveProgress({ ...opts, deviceId: () => store.session?.deviceId }, realDeps())
  onMounted(live.start)
  onBeforeUnmount(live.stop)
}
