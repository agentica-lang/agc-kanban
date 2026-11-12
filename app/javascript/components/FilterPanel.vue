<script setup>
import { computed } from "vue";
import { active, options } from "../filters.js";

// The filter choices, in the drawer that the Filters button opens. Each chip is a toggle; "Clear" takes every filter
// off. The chips come from all the cards of the board, not from the ones that show, so a selected chip never
// disappears with its cards.
var props = defineProps({ store: Object, cards: Array });
var filters = computed(function () { return props.store.filters.value; });
var chips = computed(function () { return options(props.cards, filters.value); });
</script>

<template>
  <div class="filter-panel">
    <section class="filter-group" aria-label="Ready">
      <button type="button" class="chip" :aria-pressed="filters.ready" @click="store.ready()">Ready only</button>
    </section>
    <section class="filter-group" aria-labelledby="filter-agent">
      <h3 id="filter-agent">Agent</h3>
      <p v-if="!chips.claimers.length" class="empty">No card is claimed.</p>
      <button v-for="name in chips.claimers" :key="'c:' + name" type="button" class="chip" :aria-pressed="filters.claimer === name" @click="store.claimer(name)">{{ name }}</button>
    </section>
    <section class="filter-group" aria-labelledby="filter-labels">
      <h3 id="filter-labels">Labels</h3>
      <p v-if="!chips.labels.length" class="empty">No card has a label.</p>
      <button v-for="name in chips.labels" :key="'l:' + name" type="button" class="chip" :aria-pressed="filters.labels.indexOf(name) !== -1" @click="store.label(name)">{{ name }}</button>
    </section>
    <button v-if="active(filters)" type="button" class="filters-clear" @click="store.clear()">Clear all</button>
  </div>
</template>
