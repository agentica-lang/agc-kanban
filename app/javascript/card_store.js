import { reactive } from "vue";
import { getJSON, latest } from "./api.js";

var REFETCH_MS = 80; // a burst of events of the card is one fetch

// The detail of the open card (`/api/cards/:id`: the card, its comments and its time in each column). `show(id)`
// fetches a card, `changed(id)` fetches it again when an event names it (or names no card: after a reconnect).
// `receivedAt` is the local time of the answer, from which the panel counts the time of an open card on.
export function useCard() {
  var state = reactive({ id: null, detail: null, error: "", receivedAt: 0 });
  var fetchCard = null;
  var timer = null;

  function show(id) {
    clearTimeout(timer);
    timer = null;
    state.id = id;
    state.detail = null;
    state.error = "";
    if (id === null) {
      fetchCard = null;
      return;
    }
    // A new sequence per card: an answer for the card shown before can never land on this one.
    fetchCard = latest(function () {
      return getJSON("/api/cards/" + id);
    }, function (detail, fresh) {
      state.detail = detail;
      state.receivedAt = Date.now();
      if (fresh) {
        state.error = "";
      }
    }, function (error) {
      state.error = error.message;
    });
    fetchCard();
  }

  function changed(id) {
    if (fetchCard !== null && (id === null || id === state.id) && timer === null) {
      timer = setTimeout(function () {
        timer = null;
        fetchCard();
      }, REFETCH_MS);
    }
  }

  state.show = show;
  state.changed = changed;
  return state;
}
