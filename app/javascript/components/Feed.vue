<script setup>
import { computed, inject, onBeforeUnmount, ref } from "vue";
import { GROUPS, byDay, entry, relative } from "../feed.js";

var TICK_MS = 30000; // how often "5 min ago" is worked out again

// The activity of the board as sentences, by day, newest first. An entry of a card opens it in the drawer.
var props = defineProps({ state: Object });
var openCard = inject("openCard");
var now = ref(Date.now());
var tick = setInterval(function () { now.value = Date.now(); }, TICK_MS);
onBeforeUnmount(function () { clearInterval(tick); });

// The filter works on the events loaded; "Ver más" loads older ones.
var agent = ref("");
var group = ref("");

var titles = computed(function () {
  var map = {};
  props.state.cards.forEach(function (card) { map[card.id] = card.title; });
  return map;
});

var entries = computed(function () {
  return props.state.feed.map(function (event) { return entry(event, titles.value); });
});

var agents = computed(function () {
  // A Set, not an object: an agent named `__proto__` is a name like another.
  var seen = new Set();
  entries.value.forEach(function (one) { seen.add(one.actor); });
  return Array.from(seen).sort();
});

var days = computed(function () {
  var shown = entries.value.filter(function (one) {
    return (agent.value === "" || one.actor === agent.value) && (group.value === "" || one.group === group.value);
  });
  return byDay(shown, now.value);
});

function ago(ms) {
  return relative(ms, now.value);
}

function exact(ms) {
  return new Date(ms).toLocaleString();
}

// A plain click opens the card in the drawer; a click with a modifier keeps the link (a new tab with `?card=`).
function onClick(event, card) {
  if (event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
    event.preventDefault();
    openCard(card);
  }
}
</script>

<template>
  <div class="feed">
    <div v-if="state.feed.length" class="feed-filter">
      <select v-model="agent" aria-label="Filter by agent">
        <option value="">All agents</option>
        <option v-for="name in agents" :key="name" :value="name">{{ name }}</option>
      </select>
      <select v-model="group" aria-label="Filter by kind">
        <option value="">All kinds</option>
        <option v-for="pair in GROUPS" :key="pair[0]" :value="pair[0]">{{ pair[1] }}</option>
      </select>
    </div>
    <p v-if="state.more && (agent !== '' || group !== '')" class="feed-note">The filter applies to the events loaded; "Ver más" loads older ones.</p>
    <p v-if="!state.feed.length" class="empty">No activity yet.</p>
    <p v-else-if="!days.length" class="empty">Nothing matches the filter.</p>
    <section v-for="one in days" :key="one.key" class="feed-day">
      <h3>{{ one.label }}</h3>
      <ul>
        <li v-for="item in one.entries" :key="item.id" :class="['kind-' + item.group, { 'to-done': item.toDone }]">
          <span class="mark" aria-hidden="true"></span>
          <a v-if="item.card !== null" class="entry" :href="'?card=' + item.card" @click="onClick($event, item.card)">
            <span class="sentence">
              <b>{{ item.actor }}</b> {{ item.verb }} <b class="ref">#{{ item.card }}</b> <span v-if="item.title" class="title">{{ item.title }}</span>
              <template v-if="item.reordered"> in {{ item.to }}</template>
              <template v-else-if="item.from"> from {{ item.from }} &rarr; {{ item.to }}</template>
              <template v-else-if="item.to"> to {{ item.to }}</template>
              <template v-if="item.excerpt">: <q>{{ item.excerpt }}</q></template>
            </span>
            <time :datetime="new Date(item.at).toISOString()" :title="exact(item.at)">{{ ago(item.at) }}</time>
          </a>
          <div v-else class="entry">
            <span class="sentence"><b>{{ item.actor }}</b> {{ item.verb }} <b v-if="item.name">{{ item.name }}</b></span>
            <time :datetime="new Date(item.at).toISOString()" :title="exact(item.at)">{{ ago(item.at) }}</time>
          </div>
        </li>
      </ul>
    </section>
    <button v-if="state.more" class="more" type="button" :disabled="state.loading" @click="state.loadMore()">Ver más</button>
    <p v-if="state.loadError" class="empty">No se pudo cargar.</p>
  </div>
</template>
