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
      <div class="brand">
        <img class="logo" src="/argosy_mark.svg" alt="Argosy" @click="goHome" />
        <button
          class="bar-search"
          type="button"
          aria-label="Search the Manifest"
          @click="openSearch"
        >
          <span class="mag">⌕</span> <span class="label">Search the Manifest…</span>
        </button>
      </div>
      <div class="bar-right">
        <button class="pill" type="button" aria-label="Browse" @click="nav('library')">
          <span class="i">▤</span> <span class="label">Browse</span>
        </button>
        <button class="pill" type="button" aria-label="Vaults" @click="nav('vaults')">
          <span class="i">▣</span> <span class="label">Vaults</span>
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
              <button
                v-if="session.canManageServer"
                class="menu-item"
                type="button"
                @click="nav('accounts')"
              >
                <span class="mi">⚿</span> Accounts
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

/* Phones (ARGY-166). The desktop bar is one non-wrapping flex row whose
   min-content width is ~590px, so on a phone the right-hand group overflowed
   past the fixed bar's right edge — and since the bar is `position: fixed`
   there's no horizontal scroll to reach it, so Browse, Vaults and the profile
   avatar were simply unreachable. That stranded Settings, Fleet, Profiles and
   Log out, which live only behind the avatar.

   Collapse to: [ship mark] [⌕]  …  [Browse] [Vaults] [avatar]. */
@media (max-width: 720px) {
  .bar {
    gap: 10px;
    padding: 12px 14px;
  }
  .brand {
    /* Let the brand pill absorb the squeeze instead of shoving the controls
       off-screen; without min-width:0 a flex item won't shrink below content. */
    min-width: 0;
    gap: 4px;
    padding: 5px 6px 5px 10px;
  }
  /* Mark only, no wordmark. argosy_mark.svg is a 630x175 lockup, so crop rather
     than ship a second asset: `cover` in a 30x26 box scales by height (26/175)
     and reveals source x 0..202 — the ship, ending before the ARGOSY wordmark. */
  .logo {
    width: 30px;
    height: 26px;
    object-fit: cover;
    object-position: left center;
  }
  .bar-search {
    width: auto;
    margin-left: 2px;
    padding: 8px 10px;
    border-left: none;
  }
  .bar-search .label {
    display: none;
  }
  .mag {
    font-size: 19px;
  }
  .bar-right {
    gap: 8px;
  }
  .pill {
    padding: 9px 13px;
    gap: 6px;
  }
  .avatar {
    flex: none;
  }
  .inner {
    padding: 82px 16px 72px;
  }
}

/* Only the very narrowest phones drop the Browse/Vaults labels — ▤ and ▣ don't
   say much on their own, and measured at 360px the labelled pills still leave
   ~20px of slack, so every mainstream phone keeps its words. The avatar is never
   what gets dropped: it is the sole route to Settings, Fleet, Profiles and Log
   out, which is exactly what made the original overflow a dead end. */
@media (max-width: 350px) {
  .pill .label {
    display: none;
  }
  .pill {
    padding: 9px 11px;
  }
  .pill .i {
    font-size: 15px;
  }
}
</style>
