<script setup>
import { nextTick, ref, watch } from "vue";

var props = defineProps({ card: Object, blocked: Boolean, flash: Number });
var flashing = ref(props.flash > 0);

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
  <article class="card" :class="['priority-' + card.priority, { changed: flashing, 'card-done': card.done }]">
    <div class="title"><span class="id">#{{ card.id }}</span> {{ card.title }}</div>
    <div class="meta">
      <span v-if="card.claimed_by" class="claimer" :style="'--hue:' + hue(card.claimed_by)">{{ card.claimed_by }}</span>
      <span v-if="blocked" class="blocked">blocked by {{ card.depends_on.map(function (id) { return "#" + id; }).join(" ") }}</span>
      <span v-for="label in card.labels" :key="label" class="label">{{ label }}</span>
    </div>
  </article>
</template>
