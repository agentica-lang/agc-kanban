import { reactive } from "vue";
import { getJSON, latest } from "./api.js";

var REFETCH_MS = 80; // a burst of events of the card is one fetch

// The detail of the open card (`/api/cards/:id`: the card, its comments and its time in each column). `show(id)`
// fetches a card, `changed(id)` fetches it again when an event names it (or names no card: after a reconnect).
// `receivedAt` is the local time of the answer, from which the panel counts the time of an open card on.
export function useCard() {
  var state = reactive({ id: null, detail: null, error: "", receivedAt: 0 });
  var fetchCard = null; // the fetch of the card shown; a new one on each `show`
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
    // A new sequence per `show` orders the answers for that card. An answer (or failure) of an earlier `show` is
    // dropped: another card is shown, the panel closed, or the same card was opened again.
    var mine = latest(function () {
      return getJSON("/api/cards/" + id);
    }, function (detail, fresh) {
      if (fetchCard !== mine) {
        return;
      }
      state.detail = detail;
      state.receivedAt = Date.now();
      if (fresh) {
        state.error = "";
      }
    }, function (error) {
      if (fetchCard === mine) {
        state.error = error.message;
      }
    });
    fetchCard = mine;
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
