<script setup>
import { computed, ref } from "vue";
import { active, options } from "../filters.js";

// The filter choices, in the drawer that the Filters button opens. Each chip is a toggle; "Clear" takes every filter
// off. The chips come from all the cards of the board, not from the ones that show, so a selected chip never
// disappears with its cards.
// The search box is the first group: it narrows the board to the cards that the server ranks for the text, together
// with the filters below it. Escape clears the text; with no text it closes the drawer, as everywhere else.
var props = defineProps({ store: Object, cards: Array, search: Object });
var input = ref(null);
defineExpose({ focus: function () { input.value && input.value.focus(); } });
function onEscape(event) {
  if (props.search.q.value !== "") {
    props.search.clear();
    event.stopPropagation();
  }
}
var filters = computed(function () { return props.store.filters.value; });
var chips = computed(function () { return options(props.cards, filters.value); });
</script>

<template>
  <div class="filter-panel">
    <section class="filter-group" aria-label="Search">
      <input ref="input" type="search" class="search-input" aria-label="Search cards" placeholder="Search cards (press /)" autocomplete="off" :value="search.q.value" @input="search.set($event.target.value)" @keydown.esc="onEscape" />
      <p v-if="search.failed.value" class="empty" role="status">The search failed; showing every card.</p>
      <p v-else-if="search.on() && search.count() !== null" class="empty" role="status">{{ search.count() }} {{ search.count() === 1 ? "card" : "cards" }} found, best first</p>
    </section>
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
    <button v-if="active(filters) || search.on()" type="button" class="filters-clear" @click="store.clear(); search.clear()">Clear all</button>
  </div>
</template>
