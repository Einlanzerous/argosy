<script setup lang="ts">
import { computed, ref } from 'vue'
import { RouterView, useRoute, useRouter } from 'vue-router'
import SearchOverlay from '@/components/SearchOverlay.vue'
import { ui, openSearch } from '@/lib/ui'
import { useSessionStore } from '@/stores/session'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const menuOpen = ref(false)

// Home and Library are full-bleed (their own backdrops sit under the floating
// bar); other screens get padded so content clears the fixed bar.
const fullBleed = computed(() => ['home', 'library'].includes(String(route.name)))
// The bar's pill search is hidden on Library, which has its own inline search.
const showBarSearch = computed(() => String(route.name) !== 'library')
const initial = computed(() => (session.profileName || 'Argosy').charAt(0).toUpperCase())
const isAdmin = computed(() => session.session?.role === 'admin')

function goHome(): void {
  void router.push({ name: 'home' })
}
function nav(name: string): void {
  menuOpen.value = false
  void router.push({ name })
}
function logout(): void {
  menuOpen.value = false
  session.logout()
  void router.push({ name: 'login' })
}
</script>

<template>
  <div class="app">
    <!-- floating top bar -->
    <header class="bar">
      <div class="brand" :class="{ 'logo-only': !showBarSearch }">
        <img class="logo" src="/argosy_logo_dark.png" alt="Argosy" @click="goHome" />
        <button v-if="showBarSearch" class="bar-search" type="button" @click="openSearch">
          <span class="mag">⌕</span> Search the Manifest…
        </button>
      </div>
      <div class="bar-right">
        <button class="pill" type="button" @click="nav('library')">
          <span class="i">▤</span> Browse
        </button>
        <button class="pill" type="button" @click="nav('vaults')">
          <span class="i">▣</span> Vaults
        </button>
        <div class="profile">
          <button class="avatar" type="button" @click="menuOpen = !menuOpen">{{ initial }}</button>
          <template v-if="menuOpen">
            <div class="menu-scrim" @click="menuOpen = false" />
            <div class="menu">
              <div class="menu-head">
                <div class="menu-name">{{ session.profileName || 'Signed in' }}</div>
                <div class="menu-sub">{{ session.deviceName || 'this device' }}</div>
              </div>
              <button class="menu-item" type="button" @click="nav('settings')">
                <span class="mi">⚙</span> Settings
              </button>
              <button class="menu-item" type="button" @click="nav('fleet')">
                <span class="mi">⛴</span> Fleet · Devices
              </button>
              <button v-if="isAdmin" class="menu-item" type="button" @click="nav('profiles')">
                <span class="mi">☻</span> Profiles
              </button>
              <button class="menu-item danger" type="button" @click="logout">
                <span class="mi">⎋</span> Log out
              </button>
            </div>
          </template>
        </div>
      </div>
    </header>

    <main>
      <div :class="{ inner: !fullBleed }">
        <RouterView />
      </div>
    </main>

    <SearchOverlay v-if="ui.searchOpen" />
  </div>
</template>

<style scoped>
.app {
  position: relative;
  min-height: 100vh;
}
.bar {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 30;
  display: flex;
  align-items: center;
  gap: 18px;
  padding: 18px 40px;
  background: linear-gradient(#171717e0 10%, rgba(23, 23, 23, 0));
}
/* Logo + search share one translucent pill so the brand reads as a single
   light surface instead of two clunky boxes. */
.brand {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 8px 6px 16px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.42);
  backdrop-filter: blur(10px);
}
.brand.logo-only {
  padding: 7px 18px;
}
.logo {
  width: 104px;
  height: auto;
  flex: none;
  cursor: pointer;
  /* The PNG has a baked-in dark background; screen blending drops it so only
     the cream ship + wordmark float on the pill (no transparent asset needed). */
  mix-blend-mode: screen;
}
.bar-search {
  display: flex;
  align-items: center;
  gap: 9px;
  width: 256px;
  margin-left: 4px;
  padding: 9px 16px 9px 14px;
  border: none;
  border-left: 1px solid var(--arg-line-2);
  border-radius: 0;
  background: transparent;
  color: #8a8a82;
  font: 500 13.5px var(--arg-body);
  cursor: text;
  text-align: left;
}
.bar-search:hover {
  color: var(--arg-cream);
}
.mag {
  color: var(--arg-accent);
  font-size: 15px;
}
.bar-right {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 9px;
}
.pill {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 9px 16px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.5);
  backdrop-filter: blur(8px);
  color: #e4e4dc;
  font: 600 13px var(--arg-body);
  cursor: pointer;
}
.pill:hover {
  border-color: var(--arg-accent);
}
.pill .i {
  color: var(--arg-accent);
}
.profile {
  position: relative;
}
.avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  border: 1px solid rgba(234, 234, 229, 0.2);
  background: linear-gradient(135deg, var(--arg-accent), #7a5d2c);
  display: flex;
  align-items: center;
  justify-content: center;
  font: 700 14px var(--arg-display);
  color: var(--arg-bg);
  cursor: pointer;
}
.avatar:hover {
  filter: brightness(1.08);
}
.menu-scrim {
  position: fixed;
  inset: 0;
  z-index: 40;
}
.menu {
  position: absolute;
  top: calc(100% + 12px);
  right: 0;
  z-index: 41;
  width: 222px;
  padding: 8px;
  border-radius: 13px;
  background: var(--arg-panel-2);
  border: 1px solid var(--arg-line-2);
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.55);
  animation: argRise 0.18s ease both;
}
.menu-head {
  padding: 10px 12px 12px;
  border-bottom: 1px solid var(--arg-line);
  margin-bottom: 6px;
}
.menu-name {
  font: 700 14px var(--arg-display);
}
.menu-sub {
  font: 500 11.5px var(--arg-body);
  color: var(--arg-mute);
}
.menu-item {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 10px 12px;
  border: none;
  border-radius: var(--arg-r-sm);
  background: transparent;
  color: #dcdcd4;
  font: 600 13.5px var(--arg-body);
  cursor: pointer;
  text-align: left;
}
.menu-item:hover {
  background: rgba(234, 234, 229, 0.06);
}
.menu-item .mi {
  color: var(--arg-accent);
  width: 16px;
}
.menu-item.danger {
  color: #cf9a86;
}
.menu-item.danger:hover {
  background: rgba(201, 106, 78, 0.12);
}
.menu-item.danger .mi {
  color: inherit;
}
main {
  min-height: 100vh;
}
.inner {
  padding: 96px 40px 90px;
}
</style>
