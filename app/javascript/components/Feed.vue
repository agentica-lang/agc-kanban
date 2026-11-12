<script setup>
defineProps({ state: Object });
</script>

<template>
  <div class="feed">
    <p v-if="!state.feed.length" class="empty">No activity yet.</p>
    <ul>
      <li v-for="event in state.feed" :key="event.id">
        <b>{{ event.kind }}</b>{{ event.card_id !== null ? " #" + event.card_id : "" }} <span class="actor">{{ event.actor }}</span>
      </li>
    </ul>
    <button v-if="state.more" class="more" type="button" :disabled="state.loading" @click="state.loadMore()">Ver más</button>
    <p v-if="state.loadError" class="empty">No se pudo cargar.</p>
  </div>
</template>
