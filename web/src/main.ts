import { createApp } from 'vue'
import { createPinia } from 'pinia'
import '@fontsource-variable/archivo'
import '@fontsource-variable/hanken-grotesk'
import App from './App.vue'
import { router } from './router'
import './style.css'

createApp(App).use(createPinia()).use(router).mount('#app')
