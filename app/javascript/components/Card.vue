<script setup>
import { computed, inject, nextTick, ref, watch } from "vue";

var props = defineProps({ card: Object, blocked: Boolean, flash: Number });
var flashing = ref(props.flash > 0);
var openCard = inject("openCard");
var openCardId = inject("openCardId");
var open = computed(function () { return openCardId.value === props.card.id; });

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
  <a class="card" :href="'?card=' + card.id" :aria-current="open ? 'true' : null" :class="['priority-' + card.priority, { changed: flashing, 'card-done': card.done, open: open }]" @click="onClick">
    <div class="title"><span class="id">#{{ card.id }}</span> {{ card.title }}</div>
    <div class="meta">
      <span v-if="card.claimed_by" class="claimer" :style="'--hue:' + hue(card.claimed_by)">{{ card.claimed_by }}</span>
      <span v-if="blocked" class="blocked">blocked by {{ card.depends_on.map(function (id) { return "#" + id; }).join(" ") }}</span>
      <span v-for="label in card.labels" :key="label" class="label">{{ label }}</span>
    </div>
  </a>
</template>
