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
      // Everything else lives inside the sidebar/topbar chrome.
      path: '/',
      component: () => import('@/layouts/AppShell.vue'),
      children: [
        { path: '', name: 'home', component: () => import('@/views/HomeView.vue') },
        { path: 'library', name: 'library', component: () => import('@/views/LibraryView.vue') },
        { path: 'movies', name: 'movies', component: () => import('@/views/LibraryView.vue') },
        { path: 'shows', name: 'shows', component: () => import('@/views/LibraryView.vue') },
        { path: 'movie/:id', name: 'movie', component: () => import('@/views/MovieDetailView.vue') },
        { path: 'series/:id', name: 'series', component: () => import('@/views/SeriesDetailView.vue') },
        { path: 'fleet', name: 'fleet', component: () => import('@/views/FleetView.vue') },
        { path: 'settings', name: 'settings', component: () => import('@/views/SettingsView.vue') },
      ],
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
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
