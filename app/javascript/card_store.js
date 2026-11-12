import { reactive, watch } from "vue";
import { getJSON, latest } from "./api.js";

var REFETCH_MS = 80; // a burst of events of the card is one fetch

// The detail of the open card (`/api/cards/:id`: the card, its comments and its time in each column). `show(id)`
// fetches a card (`gone` is true when the server has no such card), `changed(id)` fetches it again when an event names it (or names no card: after a reconnect).
// `receivedAt` is the local time of the answer, from which the panel counts the time of an open card on.
export function useCard() {
  var state = reactive({ id: null, detail: null, error: "", gone: false, receivedAt: 0 });
  var fetchCard = null; // the fetch of the card shown; a new one on each `show`
  var timer = null;

  function show(id) {
    clearTimeout(timer);
    timer = null;
    state.id = id;
    state.detail = null;
    state.error = "";
    state.gone = false;
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
        // A card that does not exist (a stale `?card=`, an old history entry): the page closes the panel.
        state.gone = error.status === 404;
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

// The card store follows the drawer: it fetches the card that the drawer shows, and a card that is gone closes the panel
// quietly (`drawer.dismiss`: no history entry). The board page calls it once, in its setup.
export function followDrawer(drawer, card) {
  watch(drawer.card, card.show, { immediate: true });
  watch(function () { return card.gone; }, function (gone) {
    if (gone) {
      drawer.dismiss(card.id);
    }
  });
}
