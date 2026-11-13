<script setup>
import { onMounted, ref } from "vue";

// The shell of a panel of the right-side drawer: a title, a close button and a body that scrolls on its own. The id is
// the one the Activity button controls. With `focus`, the title takes the focus when the panel opens, so a keyboard
// user starts in it. `modal` is the card's panel, which the stylesheet shows as a centered window on a wide screen;
// `dialog` says it is one now (the page puts `inert` on the rest only then), so it is the only one that has the role.
var props = defineProps({ title: String, focus: Boolean, modal: Boolean, dialog: Boolean });
defineEmits(["close"]);
var heading = ref(null);
onMounted(function () {
  if (props.focus) {
    heading.value.focus();
  }
});

// The title takes the focus again when the panel shows another card, as when it opens.
defineExpose({ focusTitle: function () { heading.value.focus(); } });
</script>

<template>
  <aside id="drawer" class="drawer" :class="{ 'drawer-modal': modal }" :role="dialog ? 'dialog' : null" :aria-modal="dialog ? 'true' : null" :aria-label="title">
    <header class="drawer-head">
      <h2 ref="heading" tabindex="-1">{{ title }}</h2>
      <button type="button" class="drawer-close" aria-label="Close" @click="$emit('close')">&times;</button>
    </header>
    <div class="drawer-body"><slot /></div>
  </aside>
</template>
