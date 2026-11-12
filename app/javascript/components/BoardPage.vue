<script setup>
import { computed, nextTick, onBeforeUnmount, provide, ref, watch } from "vue";
import { useBoard } from "../board_store.js";
import { useCard } from "../card_store.js";
import { useDrawer } from "../drawer.js";
import { useFilters } from "../filter_store.js";
import { active, count, matches } from "../filters.js";
import { useTheme } from "../theme.js";
import CardPanel from "./CardPanel.vue";
import Column from "./Column.vue";
import Drawer from "./Drawer.vue";
import FilterBar from "./FilterBar.vue";
import FilterPanel from "./FilterPanel.vue";
import Feed from "./Feed.vue";

var props = defineProps({ slug: String });
var drawer = useDrawer();
var theme = useTheme();
// The button names the theme it switches to.
var themeLabel = computed(function () {
  return theme.theme.value === "dark" ? "Switch to light theme" : "Switch to dark theme";
});
var panel = drawer.panel;
var card = useCard();
var state = useBoard(props.slug, card.changed);

watch(drawer.card, card.show, { immediate: true });
// A card on the board opens its detail; the open one is marked.
provide("openCard", drawer.showCard);
provide("openCardId", drawer.card);

// The filters hide cards on the board only: the feed stays the whole history of the board, and the card named by `?card=`
// opens even when it is hidden. A hidden card still counts for the blocked marks below.
var filter = useFilters();
provide("filter", filter);

// When the filters panel closes (Escape, ✕, the button, a tap beside it), the focus goes back to the Filters button
// instead of the page, also when the activity shows again behind it. A card that opens keeps the focus in its panel, and
// a click on another header button (Activity) keeps it on that button.
var filtersButton = ref(null);
watch(panel, function (now, before) {
  if (before === "filters" && now !== "card") {
    nextTick(function () {
      var focused = document.activeElement;
      if (!focused || focused === document.body || focused === filtersButton.value) {
        filtersButton.value.focus();
      }
    });
  }
});

// Escape closes the panel that is open.
function onKey(event) {
  if (event.key === "Escape" && panel.value !== "") {
    drawer.close();
  }
}
document.addEventListener("keydown", onKey);
onBeforeUnmount(function () { document.removeEventListener("keydown", onKey); });

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
    var all = state.cards.filter(function (card) { return card.column_id === column.id; });
    var cards = all
      .filter(function (card) { return matches(card, filter.filters.value); })
      .sort(function (a, b) { return a.position - b.position; });
    return { column: column, cards: cards, total: all.length };
  });
});

var shown = computed(function () {
  return columns.value.reduce(function (sum, entry) { return sum + entry.cards.length; }, 0);
});
var filtering = computed(function () { return active(filter.filters.value); });
// The Filters button says how many are on: "Filters · 2".
var filterCount = computed(function () { return count(filter.filters.value); });
// A phone shows only the funnel and a badge, so the name says the count too.
var filtersLabel = computed(function () { return filterCount.value ? "Filters · " + filterCount.value : "Filters"; });
</script>

<template>
  <main v-if="state.error && !state.board">
    <h1>Board {{ slug }}</h1>
    <p class="empty">{{ state.error }}</p>
  </main>
  <p v-else-if="!state.board" class="empty">Loading...</p>
  <div v-else class="board-page">
    <header class="top">
      <a href="/boards">Boards</a>
      <h1>{{ state.board.name }}</h1>
      <button type="button" class="toggle" :aria-label="themeLabel" :title="themeLabel" @click="theme.toggle()">
        <svg v-if="theme.theme.value === 'dark'" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><circle cx="8" cy="8" r="3" fill="currentColor" /><path d="M8 1v2M8 13v2M1 8h2M13 8h2M3.05 3.05l1.41 1.41M11.54 11.54l1.41 1.41M3.05 12.95l1.41-1.41M11.54 4.46l1.41-1.41" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" /></svg>
        <svg v-else viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M13.5 10.2A6 6 0 0 1 5.8 2.5a6 6 0 1 0 7.7 7.7z" fill="currentColor" /></svg>
      </button>
      <button ref="filtersButton" type="button" class="toggle toggle-filters" :aria-label="filtersLabel" :title="filtersLabel" aria-controls="drawer" :aria-expanded="panel === 'filters'" :class="{ on: filterCount > 0 }" @click="drawer.toggleFilters()">
        <svg class="filters-icon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M2 3h12l-4.5 5.5V13l-3-1.5v-3z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" /></svg>
        <span class="filters-word">{{ filtersLabel }}</span>
        <span v-if="filterCount" class="badge" aria-hidden="true">{{ filterCount }}</span>
      </button>
      <button type="button" class="toggle" aria-label="Activity" title="Activity" aria-controls="drawer" :aria-expanded="panel === 'activity'" @click="drawer.toggleActivity()">
        <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M2 3h1.5v1.5H2zM5 3h9v1.5H5zM2 7.25h1.5v1.5H2zM5 7.25h9v1.5H5zM2 11.5h1.5V13H2zM5 11.5h9V13H5z" fill="currentColor" /></svg>
      </button>
    </header>
    <p v-if="state.error" class="banner">Could not refresh the board: {{ state.error }}</p>
    <FilterBar :store="filter" :shown="shown" />
    <div class="board-body">
      <main class="board">
        <Column v-for="entry in columns" :key="entry.column.id" :column="entry.column" :cards="entry.cards" :total="entry.total" :filtering="filtering" :blocked="blocked" :flash="state.flash" />
        <p v-if="!columns.length" class="empty">This board has no columns.</p>
      </main>
      <div v-if="panel !== ''" class="backdrop" aria-hidden="true" @click="drawer.close()"></div>
      <Drawer v-if="panel === 'activity'" title="Activity" @close="drawer.close()">
        <Feed :state="state" />
      </Drawer>
      <Drawer v-else-if="panel === 'filters'" title="Filters" focus @close="drawer.close()">
        <FilterPanel :store="filter" :cards="state.cards" />
      </Drawer>
      <Drawer v-else-if="panel === 'card'" :title="'Card #' + drawer.card.value" @close="drawer.close()">
        <CardPanel :state="card" :slug="slug" @open="drawer.showCard" />
      </Drawer>
    </div>
  </div>
</template>
