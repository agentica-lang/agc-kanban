<script setup>
import { computed } from "vue";
import { active, activeChips } from "../filters.js";

// Above the columns: only the filters that are on, each a chip whose ✕ takes it off, and "Clear". Nothing when no
// filter is on; the choices are in the panel of the Filters button.
// `inert` takes it out of the keyboard order and the accessibility tree while a modal lies over the board; it has two
// roots, so the attribute cannot fall through.
var props = defineProps({ store: Object, shown: Number, inert: Boolean });
var filters = computed(function () { return props.store.filters.value; });
var chips = computed(function () { return activeChips(filters.value); });
var on = computed(function () { return active(filters.value); });

function remove(chip) {
  if (chip.kind === "ready") {
    props.store.ready();
  } else if (chip.kind === "claimer") {
    props.store.claimer(chip.name);
  } else {
    props.store.label(chip.name);
  }
}
</script>

<template>
  <div v-if="on" class="filters" :inert="inert" role="group" aria-label="Active filters">
    <button v-for="chip in chips" :key="chip.kind + ':' + chip.name" type="button" class="chip chip-on" :aria-label="'Remove filter ' + chip.text" @click="remove(chip)"><span class="chip-text">{{ chip.text }}</span> <span aria-hidden="true">✕</span></button>
    <button type="button" class="filters-clear" @click="store.clear()">Clear</button>
  </div>
  <p v-if="on && shown === 0" class="filters-none empty" :inert="inert">No card matches the filters. <button type="button" class="filters-clear" @click="store.clear()">Clear them</button></p>
</template>
