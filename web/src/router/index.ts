import { createRouter, createWebHistory } from 'vue-router'
import { setUnauthorizedHandler } from '@/api/client'
import { useSessionStore } from '@/stores/session'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      meta: { public: true },
      component: () => import('@/views/LoginView.vue'),
    },
    {
      // Full-screen, chrome-less playback surface.
      path: '/player/:id',
      name: 'player',
      component: () => import('@/views/PlayerView.vue'),
    },
    {
      // Everything else lives inside the topbar chrome.
      path: '/',
      component: () => import('@/layouts/AppShell.vue'),
      children: [
        { path: '', name: 'home', component: () => import('@/views/HomeView.vue') },
        // Library is the single browse surface; Movies/Shows are a ?kind= filter,
        // not separate pages. (/movie/:id and /series/:id are item detail pages.)
        { path: 'library', name: 'library', component: () => import('@/views/LibraryView.vue') },
        {
          path: 'movie/:id',
          name: 'movie',
          component: () => import('@/views/MovieDetailView.vue'),
        },
        {
          path: 'series/:id',
          name: 'series',
          component: () => import('@/views/SeriesDetailView.vue'),
        },
        { path: 'vaults', name: 'vaults', component: () => import('@/views/VaultsView.vue') },
        {
          path: 'vault/:id',
          name: 'vault',
          component: () => import('@/views/VaultDetailView.vue'),
        },
        { path: 'fleet', name: 'fleet', component: () => import('@/views/FleetView.vue') },
        // Household profile management (ARGY-65). Admin-gated in the UI and on
        // the server; viewers reaching it directly just see a note.
        {
          path: 'profiles',
          name: 'profiles',
          component: () => import('@/views/ProfilesView.vue'),
        },
        // Approve a TV pairing code (ARGY-112). Auth-gated like the rest of the
        // shell, so the household member is signed in when they approve.
        { path: 'link', name: 'link', component: () => import('@/views/LinkView.vue') },
        { path: 'settings', name: 'settings', component: () => import('@/views/SettingsView.vue') },
      ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})

// A deploy atomically swaps every content-hashed asset the embedded SPA serves,
// so a session opened before it can navigate into a lazy route whose chunk now
// 404s — the import rejects and the navigation silently aborts, which reads as
// "the Back button is dead" (ARGY-164). Recover by hard-loading the target URL:
// the fresh index references live chunks. The sessionStorage latch stops a
// reload loop when the target is broken even when freshly served; a successful
// navigation clears it so the *next* deploy can trigger a reload again.
const CHUNK_RELOAD_KEY = 'argosy.chunkReload'

function isStaleChunkError(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err)
  return /dynamically imported module|Importing a module script|error loading|Unable to preload CSS/i.test(
    msg,
  )
}

router.onError((err, to) => {
  if (!isStaleChunkError(err)) return
  if (sessionStorage.getItem(CHUNK_RELOAD_KEY) === to.fullPath) return
  sessionStorage.setItem(CHUNK_RELOAD_KEY, to.fullPath)
  window.location.assign(to.fullPath)
})

router.afterEach(() => {
  sessionStorage.removeItem(CHUNK_RELOAD_KEY)
})

router.beforeEach(async (to) => {
  const session = useSessionStore()
  if (!session.ready) await session.restore()

  if (to.meta.public) {
    return session.isAuthenticated ? { name: 'home' } : true
  }
  if (!session.isAuthenticated) {
    const redirect = to.fullPath !== '/' ? to.fullPath : undefined
    return { name: 'login', query: redirect ? { redirect } : undefined }
  }
  return true
})

// A revoked/expired token drops us back to sign-in.
setUnauthorizedHandler(() => {
  useSessionStore().logout()
  void router.push({ name: 'login' })
})
