<script setup lang="ts">
import { RouterView } from 'vue-router'
</script>

<template>
  <!-- Key the player by its full path so navigating episode→episode (auto-advance)
       remounts PlayerView, giving it a clean teardown/setup of the video element,
       HLS, and transcode session. Other routes key by their top-level record path
       so the AppShell stays mounted across child navigations. -->
  <RouterView v-slot="{ Component, route }">
    <component
      :is="Component"
      :key="route.name === 'player' ? route.fullPath : route.matched[0]?.path"
    />
  </RouterView>
</template>
