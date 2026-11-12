<script setup>
import { Markdown } from "../markdown.js";
import CardTimes from "./CardTimes.vue";

// The detail of the open card, read-only. A dependency opens that card in the same panel.
defineProps({ state: Object });
defineEmits(["open"]);

function when(ms) {
  return new Date(ms).toLocaleString();
}
</script>

<template>
  <p v-if="!state.detail" class="empty">{{ state.error || "Loading..." }}</p>
  <div v-else class="detail">
    <p v-if="state.error" class="banner">Could not refresh the card: {{ state.error }}</p>
    <h3><span class="id">#{{ state.detail.card.id }}</span> {{ state.detail.card.title }}</h3>
    <dl>
      <dt>Column</dt>
      <dd>{{ state.detail.card.column }}</dd>
      <dt>Claimed by</dt>
      <dd>{{ state.detail.card.claimed_by || "free" }}</dd>
      <dt>Priority</dt>
      <dd>{{ state.detail.card.priority }}</dd>
      <template v-if="state.detail.card.labels.length">
        <dt>Labels</dt>
        <dd><span v-for="label in state.detail.card.labels" :key="label" class="label">{{ label }}</span></dd>
      </template>
      <template v-if="state.detail.card.branch">
        <dt>Branch</dt>
        <dd><code>{{ state.detail.card.branch }}</code></dd>
      </template>
      <template v-if="state.detail.card.worktree">
        <dt>Worktree</dt>
        <dd><code>{{ state.detail.card.worktree }}</code></dd>
      </template>
      <template v-if="state.detail.card.depends_on.length">
        <dt>Depends on</dt>
        <dd><button v-for="id in state.detail.card.depends_on" :key="id" type="button" class="ref" @click="$emit('open', id)">#{{ id }}</button></dd>
      </template>
      <template v-if="state.detail.card.blocks.length">
        <dt>Blocks</dt>
        <dd><button v-for="id in state.detail.card.blocks" :key="id" type="button" class="ref" @click="$emit('open', id)">#{{ id }}</button></dd>
      </template>
      <template v-if="state.detail.times">
        <dt>Time</dt>
        <dd><CardTimes :times="state.detail.times" :received-at="state.receivedAt" /></dd>
      </template>
    </dl>
    <Markdown v-if="state.detail.card.body" :text="state.detail.card.body" />
    <h4 class="comments-title">Comments ({{ state.detail.comments.length }})</h4>
    <ol class="comments">
      <li v-for="comment in state.detail.comments" :key="comment.id">
        <div class="by"><b>{{ comment.author }}</b> <time :datetime="new Date(comment.created_at).toISOString()">{{ when(comment.created_at) }}</time></div>
        <Markdown :text="comment.body" />
      </li>
    </ol>
  </div>
</template>
