<script setup>
import { computed, inject } from "vue";
import { plainClick } from "../drawer.js";
import { cardSearch } from "../filters.js";
import { cardLink } from "../links.js";
import { Markdown } from "../markdown.js";
import CardTimes from "./CardTimes.vue";

// The detail of the open card, read-only except for the Archive and Unarchive button. A dependency opens that card in the same panel. A card of another board
// (a dependency, or `?card=` by hand) gets only a link to its board: the live events of this page are not its own.
var props = defineProps({ state: Object, slug: String, busy: Boolean, actionError: String });
var emit = defineEmits(["open", "archive", "unarchive"]);
// The filters, so the link of a card opens the same view in a new tab, as the cards of the board do.
var boardFilter = inject("filter");
var labelStyle = inject("labelStyle", function () { return null; });

// The colors are the ones of this board's labels: a card of another board keeps the plain chips.
function chip(label) {
  return props.state.detail.card.board === props.slug ? labelStyle(label) : null;
}

function refHref(id) {
  return cardSearch(boardFilter.filters.value, id);
}

// A plain click opens the card in the panel (a step in the history); a click with a modifier keeps the link.
function onRef(event, id) {
  if (plainClick(event)) {
    event.preventDefault();
    emit("open", id);
  }
}

// The newest comment first, so a live one shows at the top. The API (and `kanban card show`) keep the oldest first.
var comments = computed(function () {
  return props.state.detail.comments.slice().sort(function (a, b) { return b.created_at - a.created_at || b.id - a.id; });
});

// The links under the body, each a link only when it is http(s). A card from a server older than links has none.
var links = computed(function () {
  return (props.state.detail.card.links || []).map(function (url) {
    return Object.assign({ url: url }, cardLink(url));
  });
});

// A card that is not done is archived by a click and a yes: the cards that wait for it stop waiting.
function archive() {
  var card = props.state.detail.card;
  if (card.done || globalThis.confirm("Archive this card? It is not done, so the cards that depend on it stop waiting for it.")) {
    emit("archive", card.id);
  }
}

function when(ms) {
  return new Date(ms).toLocaleString();
}
</script>

<template>
  <p v-if="!state.detail" class="empty">{{ state.error || "Loading..." }}</p>
  <p v-else-if="state.detail.card.board !== slug" class="empty">
    Card #{{ state.detail.card.id }} is not on this board:
    <a :href="'/boards/' + encodeURIComponent(state.detail.card.board) + '?card=' + state.detail.card.id">open it on {{ state.detail.card.board }}</a>.
  </p>
  <div v-else class="detail" :class="{ 'with-banner': state.error }">
    <p v-if="state.error" class="banner">Could not refresh the card: {{ state.error }}</p>
    <h3><span class="id">#{{ state.detail.card.id }}</span> {{ state.detail.card.title }}</h3>
    <div class="detail-main">
      <Markdown v-if="state.detail.card.body" :text="state.detail.card.body" :board="slug" />
      <template v-if="links.length">
        <h4 class="section-title">Links ({{ links.length }})</h4>
        <ul class="links">
          <li v-for="(link, index) in links" :key="index">
            <a v-if="link.href" :href="link.href" :title="link.url" target="_blank" rel="noopener noreferrer">{{ link.label }}</a>
            <span v-else>{{ link.label }}</span>
          </li>
        </ul>
      </template>
      <h4 class="section-title">Comments ({{ state.detail.comments.length }})</h4>
      <ol class="comments">
        <li v-for="comment in comments" :key="comment.id">
          <div class="by"><b>{{ comment.author }}</b> <time :datetime="new Date(comment.created_at).toISOString()">{{ when(comment.created_at) }}</time></div>
          <Markdown :text="comment.body" :board="slug" />
        </li>
      </ol>
    </div>
    <div class="detail-side">
      <dl>
        <dt>Column</dt>
        <dd>{{ state.detail.card.column }}</dd>
        <template v-if="state.detail.card.archived_at">
          <dt>Archived</dt>
          <dd>{{ when(state.detail.card.archived_at) }} (hidden from the board)</dd>
        </template>
        <dt>Claimed by</dt>
        <dd>{{ state.detail.card.claimed_by || "free" }}</dd>
        <dt>Priority</dt>
        <dd>{{ state.detail.card.priority }}</dd>
        <template v-if="state.detail.card.labels.length">
          <dt>Labels</dt>
          <dd><span v-for="label in state.detail.card.labels" :key="label" class="label" :style="chip(label)">{{ label }}</span></dd>
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
          <dd><a v-for="id in state.detail.card.depends_on" :key="id" class="ref" :href="refHref(id)" @click="onRef($event, id)">#{{ id }}</a></dd>
        </template>
        <template v-if="state.detail.card.blocks.length">
          <dt>Blocks</dt>
          <dd><a v-for="id in state.detail.card.blocks" :key="id" class="ref" :href="refHref(id)" @click="onRef($event, id)">#{{ id }}</a></dd>
        </template>
        <template v-if="state.detail.times">
          <dt>Time</dt>
          <dd><CardTimes :times="state.detail.times" :received-at="state.receivedAt" /></dd>
        </template>
      </dl>
      <p v-if="actionError" class="banner" role="alert">{{ actionError }}</p>
      <button v-if="state.detail.card.archived_at" type="button" class="action" :disabled="busy" @click="emit('unarchive', state.detail.card.id)">Unarchive</button>
      <button v-else type="button" class="action" :disabled="busy" @click="archive()">Archive</button>
    </div>
  </div>
</template>
