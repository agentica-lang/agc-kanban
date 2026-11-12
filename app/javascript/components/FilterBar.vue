<script setup>
import { computed } from "vue";
import { active, options } from "../filters.js";

// The chips above the columns. A chip is a toggle; "Clear" takes every filter off. The chips come from all the cards of
// the board, not from the ones that show, so a selected chip never disappears with its cards.
var props = defineProps({ store: Object, cards: Array, shown: Number });
var filters = computed(function () { return props.store.filters.value; });
var chips = computed(function () { return options(props.cards, filters.value); });
var on = computed(function () { return active(filters.value); });
</script>

<template>
  <div v-if="cards.length || on" class="filters" role="group" aria-label="Filters">
    <button type="button" class="chip" :aria-pressed="filters.ready" @click="store.ready()">Ready</button>
    <template v-if="chips.claimers.length">
      <span class="filters-name">Agent</span>
      <button v-for="name in chips.claimers" :key="'c:' + name" type="button" class="chip" :aria-pressed="filters.claimer === name" @click="store.claimer(name)">{{ name }}</button>
    </template>
    <template v-if="chips.labels.length">
      <span class="filters-name">Label</span>
      <button v-for="name in chips.labels" :key="'l:' + name" type="button" class="chip" :aria-pressed="filters.labels.indexOf(name) !== -1" @click="store.label(name)">{{ name }}</button>
    </template>
    <button v-if="on" type="button" class="filters-clear" @click="store.clear()">Clear</button>
  </div>
  <p v-if="on && shown === 0" class="filters-none empty">No card matches the filters. <button type="button" class="filters-clear" @click="store.clear()">Clear them</button></p>
</template>
