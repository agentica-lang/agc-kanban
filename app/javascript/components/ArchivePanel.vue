<script setup>
import { inject, onBeforeUnmount, ref } from "vue";
import { plainClick } from "../drawer.js";
import { cardSearch } from "../filters.js";

// The archive drawer: the bulk archive of the done cards that are old enough, and the archived cards of the board, each
// with its Unarchive button. The list is fetched while this panel is open and follows the archive events.
var props = defineProps({ state: Object });
var openCard = inject("openCard");
var boardFilter = inject("filter");
var days = ref(3);
var result = ref("");

props.state.watchArchived = true;
props.state.loadArchived();
onBeforeUnmount(function () { props.state.watchArchived = false; });

function cardHref(id) {
  return cardSearch(boardFilter.filters.value, id);
}

function onClick(event, id) {
  if (plainClick(event)) {
    event.preventDefault();
    openCard(id);
  }
}

function archive() {
  var n = Number(days.value);
  if (!Number.isInteger(n) || n < 0) {
    return;
  }
  result.value = "";
  props.state.archiveDone(n).then(function (answer) {
    if (answer) {
      result.value = "Archived " + answer.archived + (answer.archived === 1 ? " card." : " cards.");
    }
  });
}

function when(ms) {
  return new Date(ms).toLocaleString();
}
</script>

<template>
  <div class="archive-panel">
    <form class="archive-bulk" @submit.prevent="archive()">
      <label>Archive done cards older than
        <input v-model="days" type="number" min="0" max="36500" step="1" required class="archive-days" aria-label="Days" /> days</label>
      <button type="submit" class="action" :disabled="state.busy">Archive</button>
    </form>
    <p v-if="result" class="archive-note" role="status">{{ result }}</p>
    <p v-if="state.actionError" class="banner" role="alert">{{ state.actionError }}</p>
    <h3 class="section-title">Archived ({{ state.archived.length }})</h3>
    <p v-if="!state.archived.length" class="empty">No archived card.</p>
    <p v-else-if="state.archived.length >= state.archivedMax" class="empty">The newest {{ state.archivedMax }} are shown.</p>
    <ul class="archive-list">
      <li v-for="card in state.archived" :key="card.id">
        <a :href="cardHref(card.id)" @click="onClick($event, card.id)"><b class="ref">#{{ card.id }}</b> <span class="title">{{ card.title }}</span></a>
        <time class="archive-when" :datetime="new Date(card.archived_at).toISOString()">{{ when(card.archived_at) }}</time>
        <button type="button" class="action" :disabled="state.busy" @click="state.unarchiveCard(card.id)">Unarchive</button>
      </li>
    </ul>
  </div>
</template>
