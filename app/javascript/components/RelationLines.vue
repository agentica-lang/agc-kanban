<script setup>
import { onBeforeUnmount, onMounted, ref, watch } from "vue";
import { watchLines } from "../lines_watch.js";
import { curve, pairs, visible } from "../relations.js";

// The lines between related cards, drawn over the board in an SVG that takes no pointer. A card sits in a column that
// scrolls, in a board that scrolls, so the lines are measured from the cards on the page again after each change of the
// board (`version`), each scroll (in any of them: the event is heard on the way down) and each resize. A line whose
// card is out of sight (scrolled away, or in a collapsed column that draws no card) is left out; nothing is guessed.
var props = defineProps({ cards: Array, hot: { type: Number, default: null }, version: String });
var svg = ref(null);
var paths = ref([]);
var size = ref({ width: 0, height: 0 });
var frame = 0;
var watcher = null;

function box(id, origin, seen) {
  var element = document.querySelector('.board-body .card[data-card-id="' + id + '"]');
  if (!element) {
    return null;
  }
  seen.push(element);
  var rect = element.getBoundingClientRect();
  var column = element.closest(".cards");
  var clip = column ? column.getBoundingClientRect() : rect;
  var shown = { left: rect.left - origin.left, right: rect.right - origin.left, top: rect.top - origin.top, bottom: rect.bottom - origin.top };
  var edge = { left: clip.left - origin.left, right: clip.right - origin.left, top: clip.top - origin.top, bottom: clip.bottom - origin.top };
  return visible(shown, edge) ? shown : null;
}

function measure() {
  frame = 0;
  var host = svg.value && svg.value.parentElement;
  if (!host) {
    return;
  }
  var origin = host.getBoundingClientRect();
  var board = host.querySelector(".board");
  var view = board ? board.getBoundingClientRect() : origin;
  var area = { left: view.left - origin.left, right: view.right - origin.left, top: 0, bottom: origin.height };
  size.value = { width: origin.width, height: origin.height };
  var next = [];
  var seen = [];
  pairs(props.cards).forEach(function (pair) {
    var a = box(pair.from, origin, seen);
    var b = box(pair.to, origin, seen);
    if (a && b && visible(a, area) && visible(b, area)) {
      next.push({ key: pair.from + ">" + pair.to, d: curve(a, b), from: pair.from, to: pair.to });
    }
  });
  paths.value = next;
  watcher && watcher.sync(seen);
}

function schedule() {
  if (!frame) {
    frame = requestAnimationFrame(measure);
  }
}

onMounted(function () {
  watcher = watchLines(svg.value.parentElement, schedule, window, globalThis.ResizeObserver);
  schedule();
});

onBeforeUnmount(function () {
  watcher && watcher.stop();
  frame && cancelAnimationFrame(frame);
});

watch(function () { return props.version; }, function () { schedule(); }, { flush: "post" });

function state(path) {
  if (props.hot === undefined || props.hot === null) {
    return "";
  }
  return path.from === props.hot || path.to === props.hot ? "hot" : "dim";
}
</script>

<template>
  <svg ref="svg" class="relation-lines" :width="size.width" :height="size.height" aria-hidden="true" focusable="false">
    <defs>
      <marker id="relation-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
        <path d="M0 0 8 4 0 8z" fill="currentColor" />
      </marker>
    </defs>
    <path v-for="path in paths" :key="path.key" :d="path.d" class="relation-line" :class="state(path)" marker-end="url(#relation-arrow)" />
  </svg>
</template>
