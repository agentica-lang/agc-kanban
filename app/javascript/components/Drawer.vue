<script setup>
import { onMounted, ref } from "vue";

// The shell of a panel of the right-side drawer: a title, a close button and a body that scrolls on its own. The id is
// the one the Activity button controls. With `focus`, the title takes the focus when the panel opens, so a keyboard
// user starts in it.
var props = defineProps({ title: String, focus: Boolean, modal: Boolean });
defineEmits(["close"]);
var heading = ref(null);
onMounted(function () {
  if (props.focus) {
    heading.value.focus();
  }
});
</script>

<template>
  <aside id="drawer" class="drawer" :class="{ 'drawer-modal': modal }" :role="modal ? 'dialog' : null" :aria-modal="modal ? 'true' : null" :aria-label="title">
    <header class="drawer-head">
      <h2 ref="heading" tabindex="-1">{{ title }}</h2>
      <button type="button" class="drawer-close" aria-label="Close" @click="$emit('close')">&times;</button>
    </header>
    <div class="drawer-body"><slot /></div>
  </aside>
</template>
