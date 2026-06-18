<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useSessionStore } from '@/stores/session'

type NavItem = {
  label: string
  icon: string
  to?: string
  badge?: string
  disabled?: boolean
}

const route = useRoute()
const router = useRouter()
const session = useSessionStore()

const groups: { label: string; items: NavItem[] }[] = [
  {
    label: 'Browse',
    items: [
      { label: 'Home', icon: '◎', to: 'home' },
      { label: 'Library', icon: '▤', to: 'library' },
      { label: 'Movies', icon: '▦', to: 'movies' },
      { label: 'Shows', icon: '▥', to: 'shows' },
    ],
  },
  {
    label: 'Yours',
    items: [
      { label: 'Continue Watching', icon: '⇄', to: 'home' },
      { label: 'Collections', icon: '◈', disabled: true },
      { label: 'Downloads', icon: '⤓', disabled: true },
      { label: 'History', icon: '◷', disabled: true },
    ],
  },
  {
    label: 'System',
    items: [
      { label: 'Devices', icon: '⛴', to: 'fleet' },
      { label: 'Settings', icon: '⚙', to: 'settings' },
    ],
  },
]

const initial = computed(() => (session.profileName || 'Argosy').charAt(0).toUpperCase())

function isActive(item: NavItem): boolean {
  return item.to === route.name
}

function logout(): void {
  session.logout()
  void router.push({ name: 'login' })
}
</script>

<template>
  <aside class="sidebar">
    <img class="logo" src="/argosy_logo_dark.png" alt="Argosy" />

    <div class="search">
      <span class="icon">⌕</span>
      <input type="text" placeholder="Search the Manifest…" disabled />
    </div>

    <nav>
      <div v-for="group in groups" :key="group.label" class="group">
        <div class="group-label">{{ group.label }}</div>
        <template v-for="item in group.items" :key="item.label">
          <span v-if="item.disabled" class="nav disabled">
            <span class="nav-icon">{{ item.icon }}</span>
            <span class="nav-label">{{ item.label }}</span>
            <span class="soon">soon</span>
          </span>
          <RouterLink
            v-else
            class="nav"
            :class="{ active: isActive(item) }"
            :to="{ name: item.to }"
          >
            <span class="nav-icon">{{ item.icon }}</span>
            <span class="nav-label">{{ item.label }}</span>
            <span v-if="item.badge" class="badge">{{ item.badge }}</span>
          </RouterLink>
        </template>
      </div>
    </nav>

    <button class="profile" type="button" @click="logout" title="Sign out">
      <span class="avatar">{{ initial }}</span>
      <span class="who">
        <span class="name">{{ session.profileName || 'Signed in' }}</span>
        <span class="device">{{ session.deviceName || 'this device' }}</span>
      </span>
      <span class="signout">⎋</span>
    </button>
  </aside>
</template>

<style scoped>
.sidebar {
  width: 248px;
  flex: none;
  position: sticky;
  top: 0;
  height: 100vh;
  background: var(--arg-bg-2);
  border-right: 1px solid var(--arg-line);
  display: flex;
  flex-direction: column;
  padding: 24px 16px;
}
.logo {
  width: 150px;
  height: auto;
  margin: 6px 8px 22px;
}
.search {
  position: relative;
  margin: 0 4px 18px;
}
.search .icon {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--arg-faint);
  font-size: 13px;
}
.search input {
  width: 100%;
  padding: 10px 12px 10px 34px;
  border-radius: 9px;
  border: 1px solid rgba(234, 234, 229, 0.1);
  background: var(--arg-panel-2);
  color: var(--arg-cream);
  font: 500 13px var(--arg-body);
  outline: none;
}
.search input:focus {
  border-color: var(--arg-accent);
}
nav {
  overflow-y: auto;
}
.group {
  margin-bottom: 18px;
}
.group-label {
  padding: 0 10px 8px;
  font: 700 10px var(--arg-display);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--arg-faint-2);
}
.nav {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 9px 10px;
  margin-bottom: 2px;
  border-radius: var(--arg-r-sm);
  color: var(--arg-soft);
  font: 600 13.5px var(--arg-body);
  cursor: pointer;
}
.nav:hover {
  background: rgba(234, 234, 229, 0.05);
}
.nav.active {
  background: var(--arg-accent-bg-2);
  color: var(--arg-cream);
}
.nav.active .nav-icon {
  color: var(--arg-accent);
}
.nav.disabled {
  cursor: default;
  opacity: 0.55;
  pointer-events: none;
}
.nav-icon {
  width: 18px;
  text-align: center;
  font-size: 14px;
  color: var(--arg-faint);
}
.nav-label {
  flex: 1;
}
.badge {
  font: 700 10px var(--arg-display);
  padding: 2px 7px;
  border-radius: 999px;
  background: var(--arg-accent-bg-2);
  color: var(--arg-accent);
}
.soon {
  font: 600 9px var(--arg-display);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--arg-faint-2);
}
.profile {
  margin-top: auto;
  padding: 12px 10px;
  display: flex;
  align-items: center;
  gap: 11px;
  border: none;
  border-top: 1px solid var(--arg-line);
  background: none;
  cursor: pointer;
  text-align: left;
}
.avatar {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--arg-accent), #7a5d2c);
  display: flex;
  align-items: center;
  justify-content: center;
  font: 700 14px var(--arg-display);
  color: var(--arg-bg);
}
.who {
  flex: 1;
  display: flex;
  flex-direction: column;
}
.name {
  font: 600 13px var(--arg-body);
  color: var(--arg-cream);
}
.device {
  font: 500 11px var(--arg-body);
  color: var(--arg-faint);
}
.signout {
  color: var(--arg-faint);
  font-size: 15px;
}
.profile:hover .signout {
  color: var(--arg-accent);
}
</style>
