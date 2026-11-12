<script setup>
import { ref } from "vue";
import { getJSON } from "../api.js";

// The list of boards: not live, a reload shows a new board.
var boards = ref(null);
var error = ref("");
getJSON("/api/boards").then(function (answer) {
  boards.value = answer.boards;
}, function (failure) {
  error.value = failure.message;
});
</script>

<template>
  <main v-if="boards">
    <h1>Boards</h1>
    <ul v-if="boards.length" class="boards">
      <li v-for="board in boards" :key="board.id"><a :href="'/boards/' + encodeURIComponent(board.slug)">{{ board.name }}</a></li>
    </ul>
    <p v-else class="empty">No boards yet.</p>
  </main>
  <p v-else class="empty">{{ error || "Loading..." }}</p>
</template>
