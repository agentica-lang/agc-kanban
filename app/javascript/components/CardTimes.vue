<script setup>
import { computed, onBeforeUnmount, ref } from "vue";
import { lines } from "../times.js";

// Its own ticking component, so that the count of an open card redraws only these lines, not the comments.
var props = defineProps({ times: Object, receivedAt: Number });
var TICK_MS = 15000;
var now = ref(Date.now());
var timer = setInterval(function () { now.value = Date.now(); }, TICK_MS);
onBeforeUnmount(function () { clearInterval(timer); });

var shown = computed(function () {
  return lines(props.times, Math.max(0, now.value - props.receivedAt));
});
</script>

<template>
  <ul class="times">
    <li v-for="line in shown" :key="line">{{ line }}</li>
  </ul>
</template>
