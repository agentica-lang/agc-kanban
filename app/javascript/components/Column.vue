<script setup>
import Card from "./Card.vue";

defineProps({ column: Object, cards: Array, total: Number, filtering: Boolean, blocked: Object, flash: Object });
</script>

<template>
  <section class="column" :class="{ 'column-done': column.done }">
    <h2><span class="name">{{ column.name }}</span><span class="count" :title="filtering ? cards.length + ' of ' + total + ' cards' : null">{{ filtering ? cards.length : cards.length + (column.wip_limit ? "/" + column.wip_limit : "") }}</span></h2>
    <div class="cards">
      <Card v-for="card in cards" :key="card.id" :card="card" :blocked="blocked[card.id]" :flash="flash[card.id] || 0" />
    </div>
  </section>
</template>
