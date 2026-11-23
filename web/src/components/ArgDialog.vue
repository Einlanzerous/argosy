<script setup lang="ts">
// The one modal primitive (ARGY-326). A native <dialog> opened with showModal()
// gives what the old div scrims faked: Escape, an inert page behind it, a focus
// trap, focus on open, and top-layer stacking (so no z-index race with the app
// bar). The dialog element itself is the full-viewport scrim, so a click whose
// target is the dialog — not something inside it — is a backdrop click.
//
// Mount it with v-if like the scrims it replaces: it opens on mount and emits
// `close` however it ends (Escape, backdrop click), and the parent clears the
// state that mounts it. `closedby="any"` would do the dismissal natively but is
// not in Firefox, so the Escape and backdrop paths are handled here.
import { onBeforeUnmount, onMounted, ref } from 'vue'

const props = withDefaults(
  defineProps<{
    /** Accessible name for the dialog (the visible heading's text). */
    label: string
    /** False when only an in-dialog button may end it (Escape and backdrop do nothing). */
    dismissable?: boolean
  }>(),
  { dismissable: true },
)
const emit = defineEmits<{ close: [] }>()

const el = ref<HTMLDialogElement | null>(null)
// Where focus was before the dialog opened, so it can go back there on teardown.
// The browser does this for close(), but not reliably when the element is simply
// removed from the DOM, which is what a parent's v-if does.
let opener: Element | null = null
let tearingDown = false

onMounted(() => {
  opener = document.activeElement
  el.value?.showModal()
})

onBeforeUnmount(() => {
  tearingDown = true
  if (el.value?.open) el.value.close()
  if (opener instanceof HTMLElement && opener.isConnected) opener.focus()
})

// Escape (and any other native close) lands here; so does our own close() above,
// which must not re-emit into a parent that is already unmounting.
function onClose(): void {
  if (!tearingDown) emit('close')
}

function onCancel(e: Event): void {
  if (!props.dismissable) e.preventDefault()
}

function onBackdropClick(e: MouseEvent): void {
  if (props.dismissable && e.target === el.value) emit('close')
}
</script>

<template>
  <dialog
    ref="el"
    class="arg-dialog"
    :aria-label="label"
    @cancel="onCancel"
    @close="onClose"
    @click="onBackdropClick"
  >
    <slot />
  </dialog>
</template>

<style scoped>
/* :where() keeps these at zero specificity so a parent can restyle the scrim
   (SearchOverlay's heavier blur and padding) with an ordinary class. */
:where(.arg-dialog) {
  position: fixed;
  inset: 0;
  width: 100%;
  height: 100%;
  max-width: none;
  max-height: none;
  margin: 0;
  padding: 0;
  border: none;
  background: rgba(12, 12, 11, 0.6);
  backdrop-filter: blur(3px);
  color: inherit;
  overflow: auto;
  align-items: center;
  justify-content: center;
}
:where(.arg-dialog[open]) {
  display: flex;
}
:where(.arg-dialog)::backdrop {
  background: transparent;
}
</style>
