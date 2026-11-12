<script setup>
import { computed, inject, nextTick, ref, watch } from "vue";
import { cardSearch, selectable } from "../filters.js";

var props = defineProps({ card: Object, blocked: Boolean, flash: Number });
var flashing = ref(props.flash > 0);
var openCard = inject("openCard");
var openCardId = inject("openCardId");
var filter = inject("filter");
var open = computed(function () { return openCardId.value === props.card.id; });
// The link keeps the filters, so a middle-click opens the same view in a new tab.
var href = computed(function () { return cardSearch(filter.filters.value, props.card.id); });

// A plain click opens the detail in the drawer; a click with a modifier keeps the link (a new tab with `?card=`).
function onClick(event) {
  if (event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey) {
    event.preventDefault();
    openCard(props.card.id);
  }
}


// A color from the name, so one agent keeps one color.
function hue(name) {
  var sum = 0;
  for (var i = 0; i < name.length; i++) {
    sum = (sum * 31 + name.charCodeAt(i)) % 360;
  }
  return sum;
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
  <!-- The card is a box with a stretched title link (the whole card opens it) and real buttons above the link for the
       agent and the labels, so no control sits inside another. -->
  <div class="card" :class="['priority-' + card.priority, { changed: flashing, 'card-done': card.done, open: open }]">
    <a class="title" :href="href" :data-card="card.id" :aria-current="open ? 'true' : null" @click="onClick"><span class="id">#{{ card.id }}</span> {{ card.title }}</a>
    <div class="meta">
      <button v-if="card.claimed_by" type="button" class="claimer pick" :aria-pressed="filter.filters.value.claimer === card.claimed_by" :title="'Filter by ' + card.claimed_by" :style="'--hue:' + hue(card.claimed_by)" @click="filter.claimer(card.claimed_by)">{{ card.claimed_by }}</button>
      <span v-if="blocked" class="blocked">blocked by {{ card.depends_on.map(function (id) { return "#" + id; }).join(" ") }}</span>
      <template v-for="label in card.labels" :key="label">
        <button v-if="selectable(label)" type="button" class="label pick" :class="{ on: filter.filters.value.labels.indexOf(label) !== -1 }" :aria-pressed="filter.filters.value.labels.indexOf(label) !== -1" :title="'Filter by ' + label" @click="filter.label(label)">{{ label }}</button>
        <span v-else class="label">{{ label }}</span>
      </template>
    </div>
  </div>
</template>
