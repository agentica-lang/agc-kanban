<script setup>
import { computed, nextTick, ref, watch } from "vue";
import Card from "./Card.vue";

var props = defineProps({ column: Object, cards: Array, total: Number, filtering: Boolean, blocked: Object, flash: Object, collapsed: Boolean });
var emit = defineEmits(["toggle"]);

var count = computed(function () {
  return props.filtering ? String(props.cards.length) : props.cards.length + (props.column.wip_limit ? "/" + props.column.wip_limit : "");
});
var countTitle = computed(function () { return props.filtering ? props.cards.length + " of " + props.total + " cards" : null; });
var stripLabel = computed(function () {
  var shown = props.filtering ? props.cards.length + " of " + props.total : props.cards.length;
  var word = (props.filtering ? props.total : props.cards.length) === 1 ? "card" : "cards";
  return "Expand column " + props.column.name + ", " + shown + " " + word;
});

// The button that was pressed is gone after the toggle (the header's and the strip's are two buttons), so the focus
// moves to the one that takes its place.
var collapseButton = ref(null);
var expandButton = ref(null);
var refocus = false;

function toggle() {
  refocus = true;
  emit("toggle", props.column.id);
}

watch(function () { return props.collapsed; }, function (now) {
  if (!refocus) {
    return;
  }
  refocus = false;
  nextTick(function () {
    var button = now ? expandButton.value : collapseButton.value;
    button && button.focus();
  });
});
</script>

<template>
  <section class="column" :class="{ 'column-done': column.done, 'column-collapsed': collapsed }">
    <h2 v-if="collapsed" class="strip-heading">
      <button ref="expandButton" type="button" class="column-strip" :data-column="column.id" aria-expanded="false" :aria-label="stripLabel" :title="'Expand ' + column.name" @click="toggle">
        <svg class="chevron" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M6 3.5 10.5 8 6 12.5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>
        <span class="strip-title"><span class="count" :title="countTitle">{{ count }}</span><span class="name">{{ column.name }}</span></span>
      </button>
    </h2>
    <template v-else>
      <div class="column-head">
        <h2><span class="name">{{ column.name }}</span><span class="count" :title="countTitle">{{ count }}</span></h2>
        <button ref="collapseButton" type="button" class="column-collapse" aria-expanded="true" :aria-label="'Collapse column ' + column.name" :title="'Collapse ' + column.name" @click="toggle">
          <svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M10 3.5 5.5 8 10 12.5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" /></svg>
        </button>
      </div>
      <div class="cards">
        <Card v-for="card in cards" :key="card.id" :card="card" :blocked="blocked[card.id]" :flash="flash[card.id] || 0" />
      </div>
    </template>
  </section>
</template>
