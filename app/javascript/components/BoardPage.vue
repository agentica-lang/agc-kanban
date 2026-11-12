<script setup>
import { computed } from "vue";
import { useBoard } from "../board_store.js";
import Column from "./Column.vue";
import Feed from "./Feed.vue";

var props = defineProps({ slug: String });
var state = useBoard(props.slug);

// What a card shows that depends on the others: it is blocked while a dependency sits in a column that is not done.
var done = computed(function () {
  var map = {};
  state.board.columns.forEach(function (column) { map[column.id] = column.done; });
  return map;
});

var blocked = computed(function () {
  var byId = {};
  state.cards.forEach(function (card) { byId[card.id] = card; });
  var map = {};
  state.cards.forEach(function (card) {
    map[card.id] = !card.done && card.depends_on.some(function (id) { return byId[id] && !done.value[byId[id].column_id]; });
  });
  return map;
});

var columns = computed(function () {
  return state.board.columns.slice().sort(function (a, b) { return a.position - b.position; }).map(function (column) {
    var cards = state.cards
      .filter(function (card) { return card.column_id === column.id; })
      .sort(function (a, b) { return a.position - b.position; });
    return { column: column, cards: cards };
  });
});
</script>

<template>
  <main v-if="state.error && !state.board">
    <h1>Board {{ slug }}</h1>
    <p class="empty">{{ state.error }}</p>
  </main>
  <p v-else-if="!state.board" class="empty">Loading...</p>
  <template v-else>
    <header class="top"><a href="/boards">Boards</a><h1>{{ state.board.name }}</h1></header>
    <main class="board">
      <Column v-for="entry in columns" :key="entry.column.id" :column="entry.column" :cards="entry.cards" :blocked="blocked" :flash="state.flash" />
    </main>
    <Feed :state="state" />
  </template>
</template>
