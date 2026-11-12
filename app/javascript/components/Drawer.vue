<script setup>
// The shell of a panel of the right-side drawer: a title, a close button and a body that scrolls on its own. The id is
// the one the Activity button controls.
defineProps({ title: String });
defineEmits(["close"]);
</script>

<template>
  <aside id="drawer" class="drawer" :aria-label="title">
    <header class="drawer-head">
      <h2>{{ title }}</h2>
      <button type="button" class="drawer-close" aria-label="Close" @click="$emit('close')">&times;</button>
    </header>
    <div class="drawer-body"><slot /></div>
  </aside>
</template>
