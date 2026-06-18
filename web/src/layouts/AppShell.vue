<script setup lang="ts">
import { RouterView } from 'vue-router'
import AppSidebar from '@/components/AppSidebar.vue'
import { page } from '@/lib/page'
</script>

<template>
  <div class="shell">
    <AppSidebar />
    <main class="main">
      <div class="topbar">
        <div>
          <div class="title">{{ page.title }}</div>
          <div class="sub">{{ page.subtitle }}</div>
        </div>
        <span class="status"><span class="dot" /> Server online</span>
      </div>
      <div class="content">
        <RouterView />
      </div>
    </main>
  </div>
</template>

<style scoped>
.shell {
  display: flex;
  min-height: 100vh;
}
.main {
  flex: 1;
  min-width: 0;
  max-height: 100vh;
  overflow-y: auto;
}
.topbar {
  position: sticky;
  top: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 22px 36px;
  background: linear-gradient(#171717f2, #171717cc);
  backdrop-filter: blur(8px);
  border-bottom: 1px solid rgba(234, 234, 229, 0.06);
}
.title {
  font: 800 22px var(--arg-display);
  letter-spacing: -0.01em;
}
.sub {
  margin-top: 2px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-mute);
}
.status {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 8px 13px;
  border-radius: 999px;
  border: 1px solid rgba(234, 234, 229, 0.1);
  background: var(--arg-panel);
  font: 600 12px var(--arg-body);
  color: var(--arg-dim);
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--arg-green);
}
.content {
  padding: 30px 36px 70px;
}
</style>
