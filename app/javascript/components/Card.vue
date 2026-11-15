<script setup>
import { computed, inject, nextTick, ref, watch } from "vue";
import { hue, lightChip } from "../claimer.js";
import { plainClick } from "../drawer.js";
import { cardSearch, selectable } from "../filters.js";
import { preview } from "../display.js";
import { cardLink } from "../links.js";
import { dependency, indexOf, mark } from "../relations.js";
import { human } from "../times.js";

var props = defineProps({ card: Object, blocked: Boolean, flash: Number });
var flashing = ref(props.flash > 0);
var openCard = inject("openCard");
var openCardId = inject("openCardId");
var filter = inject("filter");
var labelStyle = inject("labelStyle", function () { return null; });
// What the card shows (the display settings of the board) and the marks of the related cards; a card drawn with
// neither (a test of the markup) shows what it showed before.
var display = inject("display", { relations: false, lines: false, labels: true, agent: true, links: false, time: false, body: false });
var relations = inject("relations", null);
var clock = inject("clock", ref(Date.now()));
var open = computed(function () { return openCardId.value === props.card.id; });
// The link keeps the filters, so a middle-click opens the same view in a new tab.
var href = computed(function () { return cardSearch(filter.filters.value, props.card.id); });

var byId = computed(function () { return indexOf(relations ? relations.cards.value : []); });
var needs = computed(function () { return props.card.depends_on.map(function (id) { return dependency(byId.value, id); }); });
var blocks = computed(function () { return props.card.blocks || []; });
var marking = computed(function () { return relations ? mark(byId.value, relations.hot.value, props.card.id) : ""; });
var links = computed(function () { return (props.card.links || []).map(cardLink); });
var lead = computed(function () { return display.body ? preview(props.card.body) : ""; });
var inColumn = computed(function () {
  return display.time && typeof props.card.since === "number" ? human(Math.max(0, clock.value - props.card.since)) : "";
});
var showMeta = computed(function () {
  return (display.agent && props.card.claimed_by) || (!display.relations && props.blocked) || (display.labels && props.card.labels.length);
});

function needLabel(need) {
  if (!need.known) {
    return "Depends on card " + need.id + ", which is no longer on the board";
  }
  return "Depends on card " + need.id + (need.done ? ", done" : ", not done yet, in " + need.column) + ". Go to it";
}

function onEnter(event) {
  if (relations && event.pointerType === "mouse") {
    relations.hover(props.card.id);
  }
}

function onLeave(event) {
  if (relations && event.pointerType === "mouse") {
    relations.hover(null);
  }
}

function onFocusOut(event) {
  if (relations && !event.currentTarget.contains(event.relatedTarget)) {
    relations.hover(null);
  }
}

// A plain click opens the detail in the drawer; a click with a modifier keeps the link (a new tab with `?card=`).
function onClick(event) {
  if (plainClick(event)) {
    event.preventDefault();
    openCard(props.card.id);
  }
}

// Each new event of the card restarts the animation: the class goes off for a frame, then on.
watch(function () { return props.flash; }, function (count) {
  flashing.value = false;
  if (count > 0) {
    nextTick(function () { requestAnimationFrame(function () { flashing.value = true; }); });
  }
});
</script>

<template>
  <!-- The card is a box with a stretched title link (the whole card opens it) and real buttons and links above the link
       for the agent, the labels, the relations and the links, so no control sits inside another. -->
  <div class="card" :data-card-id="card.id" :class="['priority-' + card.priority, { changed: flashing, 'card-done': card.done, open: open, ['mark-' + marking]: marking }]" @pointerenter="onEnter" @pointerleave="onLeave" @focusin="relations && relations.hover(card.id)" @focusout="onFocusOut">
    <a class="title" :href="href" :data-card="card.id" :aria-current="open ? 'true' : null" @click="onClick"><span class="id">#{{ card.id }}</span> {{ card.title }}</a>
    <p v-if="lead" class="preview">{{ lead }}</p>
    <div v-if="showMeta" class="meta">
      <button v-if="display.agent && card.claimed_by" type="button" class="claimer pick" :class="{ light: lightChip(hue(card.claimed_by)) }" :aria-pressed="filter.filters.value.claimer === card.claimed_by" :title="'Filter by ' + card.claimed_by" :style="'--hue:' + hue(card.claimed_by)" @click="filter.claimer(card.claimed_by)">{{ card.claimed_by }}</button>
      <span v-if="blocked && !display.relations" class="blocked">blocked by {{ card.depends_on.map(function (id) { return "#" + id; }).join(" ") }}</span>
      <template v-if="display.labels">
        <template v-for="label in card.labels" :key="label">
          <button v-if="selectable(label)" type="button" class="label pick" :class="{ on: filter.filters.value.labels.indexOf(label) !== -1 }" :style="labelStyle(label)" :aria-pressed="filter.filters.value.labels.indexOf(label) !== -1" :title="'Filter by ' + label" @click="filter.label(label)">{{ label }}</button>
          <span v-else class="label" :style="labelStyle(label)">{{ label }}</span>
        </template>
      </template>
    </div>
    <div v-if="display.relations && (needs.length || blocks.length)" class="meta relations">
      <button v-for="need in needs" :key="'n' + need.id" type="button" class="rel pick" :class="need.known && !need.done ? 'rel-wait' : 'rel-ok'" :aria-label="needLabel(need)" :title="needLabel(need)" @click="relations ? relations.reveal(need.id) : null">depends on #{{ need.id }}<span class="rel-state" aria-hidden="true">{{ need.known ? need.column : "gone" }}</span></button>
      <button v-for="id in blocks" :key="'b' + id" type="button" class="rel rel-blocks pick" :aria-label="'Blocks card ' + id + '. Go to it'" :title="'Blocks card ' + id + '. Go to it'" @click="relations ? relations.reveal(id) : null">blocks #{{ id }}</button>
    </div>
    <div v-if="(display.links && links.length) || inColumn" class="meta facts">
      <template v-if="display.links">
        <template v-for="(link, index) in links" :key="index">
          <a v-if="link.href" class="link pick" :href="link.href" target="_blank" rel="noopener noreferrer">{{ link.label }}</a>
          <span v-else class="link">{{ link.label }}</span>
        </template>
      </template>
      <span v-if="inColumn" class="time" :title="'In ' + card.column + ' for ' + inColumn">{{ inColumn }} in {{ card.column }}</span>
    </div>
  </div>
</template>
