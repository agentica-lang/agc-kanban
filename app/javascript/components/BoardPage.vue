<script setup>
import { computed, nextTick, onBeforeUnmount, provide, ref, watch } from "vue";
import { useBoard } from "../board_store.js";
import { useCollapsed } from "../collapse.js";
import { useDisplay } from "../display.js";
import { reveal } from "../reveal.js";
import { followDrawer, useCard } from "../card_store.js";
import { useDrawer } from "../drawer.js";
import { useFilters } from "../filter_store.js";
import { closesPanel } from "../outside.js";
import { active, count, matches } from "../filters.js";
import { useSearch } from "../search_store.js";
import { useTheme } from "../theme.js";
import { chipStyle, colorsOf } from "../labels.js";
import { useWide } from "../wide.js";
import ArchivePanel from "./ArchivePanel.vue";
import CardPanel from "./CardPanel.vue";
import Column from "./Column.vue";
import DisplayPanel from "./DisplayPanel.vue";
import Drawer from "./Drawer.vue";
import RelationLines from "./RelationLines.vue";
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
// The card is a modal window only on a wide screen (on a phone it is a drawer beside the board): then the page behind it
// is `inert`, so the keyboard cannot leave the window and a screen reader does not read what is behind it. The Sign out
// form is not part of this app (the layout places it), so it gets the attribute here.
var wide = useWide();
var modal = computed(function () { return panel.value === "card" && wide.value; });
var cardDrawer = ref(null);
watch(modal, function (on) {
  var logout = document.querySelector(".logout");
  if (logout) {
    logout.inert = on;
  }
}, { immediate: true });
onBeforeUnmount(function () {
  var logout = document.querySelector(".logout");
  if (logout) {
    logout.inert = false;
  }
});
var card = useCard();
var state = useBoard(props.slug, card.changed);
var collapsed = useCollapsed(props.slug);
var display = useDisplay(props.slug);
provide("display", display.settings);
watch(function () {
  return state.board && state.board.columns.map(function (column) { return column.id; });
}, function (ids) {
  if (ids) {
    collapsed.keep(ids);
  }
}, { immediate: true });

followDrawer(drawer, card);

// The card panel's Archive and Unarchive: the card fetches again at once, the board and the archive list by the event.
function archiveCard(id) {
  return state.archiveCard(id).then(function () { card.changed(id); });
}

function unarchiveCard(id) {
  return state.unarchiveCard(id).then(function () { card.changed(id); });
}
// A card on the board opens its detail; the open one is marked.
provide("openCard", drawer.showCard);
provide("openCardId", drawer.card);
var labelColors = computed(function () { return colorsOf(state.labels); });
provide("labelStyle", function (name) { return chipStyle(labelColors.value[name]) || null; });

// The filters hide cards on the board only: the feed stays the whole history of the board, and the card named by `?card=`
// opens even when it is hidden. A hidden card still counts for the blocked marks below.
var filter = useFilters();
provide("filter", filter);
var search = useSearch(props.slug, function () { return state.cards; });
var filterPanel = ref(null);

// When a panel closes (Escape, ✕, its button, a click or tap beside it) and the focus was in it or nowhere, the focus
// goes back to where the panel came from: the Filters or the Activity button, or the card's link on the board (when the
// filters hide it, the focus stays where it is). Also when another panel shows again behind it. A card that opens keeps
// the focus in its panel, and a click on another header button keeps it on that button. After a click beside the panel
// the focus moves without scrolling, so the board stays where the mouse left it (the backdrop is such a click too);
// Escape and ✕ scroll to the target. A link to another card inside the card's panel takes its title (the link is gone
// when the card changes, and the focus would fall to the page).
var filtersButton = ref(null);
var activityButton = ref(null);
var archiveButton = ref(null);
var displayButton = ref(null);
var closedByPointer = false;

function origin(closed, id) {
  if (closed === "filters") {
    return filtersButton.value;
  }
  if (closed === "activity") {
    return activityButton.value;
  }
  if (closed === "archive") {
    return archiveButton.value;
  }
  if (closed === "display") {
    return displayButton.value;
  }
  return id === null ? null : cardOrigin(id);
}

// The card's link on the board, or the strip of its column when that is collapsed.
function cardOrigin(id) {
  var link = document.querySelector('.card a.title[data-card="' + id + '"]');
  var found = state.cards.find(function (one) { return one.id === id; });
  if (link || !found || !collapsed.has(found.column_id)) {
    return link;
  }
  return document.querySelector('.column-strip[data-column="' + found.column_id + '"]');
}

watch([panel, drawer.card], function (now, before) {
  var closed = before[0];
  var quiet = closedByPointer;
  closedByPointer = false;
  if (now[0] === "card" && closed === "card" && now[1] !== before[1]) {
    nextTick(function () { cardDrawer.value && cardDrawer.value.focusTitle(); });
    return;
  }
  if (closed === "" || closed === now[0] || now[0] === "card") {
    return;
  }
  nextTick(function () {
    var focused = document.activeElement;
    var target = origin(closed, before[1]);
    if (target && (!focused || focused === document.body || focused === target)) {
      target.focus({ preventScroll: quiet });
    }
  });
});

// A tap or click on the backdrop closes the panel like a click beside it: the board stays where it is.
function closeByPointer() {
  closedByPointer = true;
  drawer.close();
}

// A click beside the open panel closes it on a wide screen too (outside.js says which clicks). The end of a drag that
// selected text is no such click, wherever it started (in the panel, on a column header); a plain click collapses the
// selection when the button goes down, so it gets here with none.
function onOutside(event) {
  if (panel.value === "" || !getSelection().isCollapsed) {
    return;
  }
  var click = { path: event.composedPath(), button: event.button, ctrlKey: event.ctrlKey, metaKey: event.metaKey,
    shiftKey: event.shiftKey, altKey: event.altKey };
  if (closesPanel(click)) {
    closedByPointer = true;
    drawer.close();
  }
}
document.addEventListener("click", onOutside);
onBeforeUnmount(function () { document.removeEventListener("click", onOutside); });

// Escape closes the panel that is open. `/` opens the filters and puts the cursor in the search box, unless the key is
// meant for a field or a combination of the browser.
function typing(target) {
  return target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
}

function onKey(event) {
  if (event.key === "Escape" && panel.value !== "") {
    drawer.close();
  } else if (event.key === "/" && !event.ctrlKey && !event.metaKey && !event.altKey && !typing(event.target) && !modal.value) {
    event.preventDefault();
    if (panel.value !== "filters") {
      drawer.toggleFilters();
    }
    nextTick(function () { filterPanel.value && filterPanel.value.focus(); });
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

// The card that is hovered or focused marks its related cards and dims the others (while the relations or the lines
// show); `reveal` takes a chip to its card: the page scrolls to it and the focus goes to its title (a card the filters
// hide, or one that is not on the board, opens in the panel instead).
var hot = ref(null);
var dim = ref(false);
var relations = {
  cards: computed(function () { return state.cards; }),
  hot: hot,
  dim: dim,
  // `via` is "pointer" or "focus": only a pointer dims the cards that are not related.
  hover: function (id, via) {
    var on = display.settings.relations || display.settings.lines;
    hot.value = on ? id : null;
    dim.value = on && via === "pointer";
  },
  reveal: function (id) {
    reveal({
      cards: function () { return state.cards; },
      collapsed: collapsed,
      document: document,
      reduced: function () { return matchMedia("(prefers-reduced-motion: reduce)").matches; },
      open: drawer.showCard,
      later: nextTick,
    }, id);
  },
};
provide("relations", relations);
watch(function () { return display.settings.relations || display.settings.lines; }, function (on) {
  if (!on) {
    hot.value = null;
  }
});

// The time in the column counts on: one tick a minute, only while it shows.
var clock = ref(Date.now());
provide("clock", clock);
var ticking = null;
watch(function () { return display.settings.time; }, function (on) {
  clearInterval(ticking);
  ticking = null;
  if (on) {
    clock.value = Date.now();
    ticking = setInterval(function () { clock.value = Date.now(); }, 60000);
  }
}, { immediate: true });
onBeforeUnmount(function () { clearInterval(ticking); });

// The lines are measured again when what they join changes: the cards shown, the collapsed columns and the setting.
var linesVersion = computed(function () {
  return [display.settings.lines, display.settings.relations, display.settings.labels, display.settings.links, display.settings.body, display.settings.agent, display.settings.time, panel.value,
    collapsed.ids(), columns.value.map(function (entry) { return entry.cards.map(function (card) { return card.id + ":" + card.depends_on.join(",") + ":" + (card.blocks || []).join(","); }).join(" "); }).join("|")].join(";");
});

var columns = computed(function () {
  return state.board.columns.slice().sort(function (a, b) { return a.position - b.position; }).map(function (column) {
    var all = state.cards.filter(function (card) { return card.column_id === column.id; });
    var cards = all
      .filter(function (card) { return matches(card, filter.filters.value) && search.matches(card); })
      .sort(function (a, b) { return search.on() ? search.rank(a) - search.rank(b) || a.position - b.position : a.position - b.position; });
    return { column: column, cards: cards, total: all.length };
  });
});

var shown = computed(function () {
  return columns.value.reduce(function (sum, entry) { return sum + entry.cards.length; }, 0);
});
var filtering = computed(function () { return active(filter.filters.value) || search.on(); });
// The Filters button says how many are on: "Filters · 2".
var filterCount = computed(function () { return count(filter.filters.value) + (search.q.value.trim() !== "" ? 1 : 0); });
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
    <header class="top" :inert="modal">
      <a href="/boards">Boards</a>
      <h1>{{ state.board.name }}</h1>
      <button type="button" class="toggle reload" :class="{ spinning: state.refreshing }" aria-label="Reload board" title="Reload board" :disabled="state.refreshing" @click="state.reload()">
        <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M13 8a5 5 0 1 1-1.6-3.7M13 2.5v3h-3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>
      </button>
      <button type="button" class="toggle" :aria-label="themeLabel" :title="themeLabel" @click="theme.toggle()">
        <svg v-if="theme.theme.value === 'dark'" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><circle cx="8" cy="8" r="3" fill="currentColor" /><path d="M8 1v2M8 13v2M1 8h2M13 8h2M3.05 3.05l1.41 1.41M11.54 11.54l1.41 1.41M3.05 12.95l1.41-1.41M11.54 4.46l1.41-1.41" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" /></svg>
        <svg v-else viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M13.5 10.2A6 6 0 0 1 5.8 2.5a6 6 0 1 0 7.7 7.7z" fill="currentColor" /></svg>
      </button>
      <button ref="filtersButton" type="button" class="toggle toggle-filters" :aria-label="filtersLabel" :title="filtersLabel" aria-controls="drawer" :aria-expanded="panel === 'filters'" :class="{ on: filterCount > 0 }" @click="drawer.toggleFilters()">
        <svg class="filters-icon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M2 3h12l-4.5 5.5V13l-3-1.5v-3z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" /></svg>
        <span class="filters-word">{{ filtersLabel }}</span>
        <span v-if="filterCount" class="badge" aria-hidden="true">{{ filterCount }}</span>
      </button>
      <button ref="displayButton" type="button" class="toggle" aria-label="Display settings" title="Display settings" aria-controls="drawer" :aria-expanded="panel === 'display'" @click="drawer.toggleDisplay()">
        <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M6.7 1.5h2.6l.4 1.9 1.2.5 1.7-1 1.8 1.8-1 1.7.5 1.2 1.9.4v2.6l-1.9.4-.5 1.2 1 1.7-1.8 1.8-1.7-1-1.2.5-.4 1.9H6.7l-.4-1.9-1.2-.5-1.7 1-1.8-1.8 1-1.7-.5-1.2-1.9-.4V6.7l1.9-.4.5-1.2-1-1.7 1.8-1.8 1.7 1 1.2-.5z" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round" /><circle cx="8" cy="8" r="2.2" fill="none" stroke="currentColor" stroke-width="1.2" /></svg>
      </button>
      <button ref="archiveButton" type="button" class="toggle" aria-label="Archive" title="Archive" aria-controls="drawer" :aria-expanded="panel === 'archive'" @click="drawer.toggleArchive()">
        <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M2 3h12v3H2zM3 6v7h10V6M6.5 9h3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>
      </button>
      <button ref="activityButton" type="button" class="toggle" aria-label="Activity" title="Activity" aria-controls="drawer" :aria-expanded="panel === 'activity'" @click="drawer.toggleActivity()">
        <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M2 3h1.5v1.5H2zM5 3h9v1.5H5zM2 7.25h1.5v1.5H2zM5 7.25h9v1.5H5zM2 11.5h1.5V13H2zM5 11.5h9V13H5z" fill="currentColor" /></svg>
      </button>
    </header>
    <p v-if="state.error" class="banner" :inert="modal">Could not refresh the board: {{ state.error }}</p>
    <FilterBar :store="filter" :shown="shown" :inert="modal" />
    <div class="board-body">
      <main class="board" :inert="modal">
        <Column v-for="entry in columns" :key="entry.column.id" :column="entry.column" :cards="entry.cards" :total="entry.total" :filtering="filtering" :blocked="blocked" :flash="state.flash" :collapsed="collapsed.has(entry.column.id)" @toggle="collapsed.toggle" />
        <p v-if="!columns.length" class="empty">This board has no columns.</p>
      </main>
      <RelationLines v-if="display.settings.lines" :cards="state.cards" :hot="hot" :version="linesVersion" />
      <div v-if="panel !== ''" class="backdrop" :class="{ 'backdrop-modal': panel === 'card' }" aria-hidden="true" @click="closeByPointer()"></div>
      <Drawer v-if="panel === 'activity'" title="Activity" @close="drawer.close()">
        <Feed :state="state" />
      </Drawer>
      <Drawer v-else-if="panel === 'filters'" title="Filters" focus @close="drawer.close()">
        <FilterPanel ref="filterPanel" :store="filter" :cards="state.cards" :search="search" :labels="state.labels" @color="state.setLabelColor" />
      </Drawer>
      <Drawer v-else-if="panel === 'card'" ref="cardDrawer" :title="'Card #' + drawer.card.value" modal :dialog="wide" focus @close="drawer.close()">
        <CardPanel :state="card" :slug="slug" :busy="state.busy" :action-error="state.actionError" @open="drawer.showCard" @archive="archiveCard" @unarchive="unarchiveCard" />
      </Drawer>
      <Drawer v-else-if="panel === 'archive'" title="Archive" @close="drawer.close()">
        <ArchivePanel :state="state" />
      </Drawer>
      <Drawer v-else-if="panel === 'display'" title="Display" focus @close="drawer.close()">
        <DisplayPanel :store="display" />
      </Drawer>
    </div>
  </div>
</template>
