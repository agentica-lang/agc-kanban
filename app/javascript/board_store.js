import { reactive } from "vue";
import { getJSON, latest } from "./api.js";
import { subscribe } from "./cable.js";

var REFETCH_MS = 80; // a burst of events (a claim and a move) is one fetch
var RETRY_MS = 2000; // the pause before the one retry of a failed feed fetch
var PAGE = 30; // events shown at first, and loaded by each "Ver m\u00e1s"
var NEWEST = Number.MAX_SAFE_INTEGER; // `before` of the newest page
var WAKE_MS = 1000; // visibilitychange, pageshow and focus of one return are one wake
var FLASH_MS = 1700; // a little longer than the CSS flash

// The one reactive state of the board page: the snapshot of the API (`board`, `cards`) and the feed. It is fetched
// again after each event the cable brings and after each confirmed subscription, so a missed broadcast never leaves a
// wrong board. `reconcile` keeps the old object of every card and of the board when it did not change, and the lists are
// keyed by id, so Vue keeps the DOM node of a card that did not change (the columns and the blocked marks are worked
// out again on each load, which is cheap) and the scroll, the focus and anything open stay.
//
// The feed is the events by id, newest first, with no duplicates (an event can come from the cable and from a fetch).
// The last PAGE events load first, `before` the oldest shown gives the older ones, and what happened since the newest
// one seen is read forward with `after`.
//
// `listener(cardId)` hears each event of a card, and `listener(null)` each confirmation (anything may have been
// missed): the open card panel fetches again then.
export function useBoard(slug, listener) {
  var events = "/api/boards/" + encodeURIComponent(slug) + "/events?limit=";
  var state = reactive({
    board: null,
    cards: [],
    feed: [],
    more: false,
    loading: false,
    loadError: false,
    refreshing: false,
    error: "",
    flash: {},
    loadMore: loadMore,
    reload: reload,
  });
  var timer = null;
  var synced = 0; // the newest event id that the feed is known to hold with nothing missing before it

  function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
  }

  function reconcile(snapshot) {
    var old = {};
    state.cards.forEach(function (card) { old[card.id] = card; });
    state.cards = snapshot.cards.map(function (card) { return old[card.id] && same(old[card.id], card) ? old[card.id] : card; });
    if (!state.board || !same(state.board, snapshot.board)) {
      state.board = snapshot.board;
    }
  }

  function oldest() {
    return state.feed[state.feed.length - 1].id;
  }

  function merge(list) {
    var byId = {};
    state.feed.concat(list).forEach(function (event) { byId[event.id] = event; });
    state.feed = Object.keys(byId).map(function (id) { return byId[id]; }).sort(function (a, b) { return b.id - a.id; });
  }

  // A failed refetch keeps the board that is shown and sets `error` (a banner); a later success clears it.
  var fetchSnapshot = latest(function () {
    return getJSON("/api/boards/" + encodeURIComponent(slug));
  }, function (snapshot, fresh) {
    if (fresh) {
      state.error = "";
    }
    reconcile(snapshot);
  }, function (error) {
    state.error = error.message;
  });

  function load() {
    timer = null;
    return fetchSnapshot();
  }

  // Runs `task` again once, after a pause, when it fails: a blip of the network must not leave a hole in the feed.
  function retried(task) {
    return task().catch(function () {
      return new Promise(function (resolve) { setTimeout(resolve, RETRY_MS); }).then(task);
    });
  }

  // One more than PAGE tells whether there is anything older, so the button hides at the end.
  function loadOlder(before) {
    return getJSON(events + (PAGE + 1) + "&before=" + before).then(function (answer) {
      state.more = answer.events.length > PAGE;
      merge(answer.events.slice(0, PAGE));
    });
  }

  function loadMore() {
    if (state.loading) {
      return;
    }
    state.loading = true;
    state.loadError = false;
    retried(function () { return loadOlder(oldest()); }).catch(function () {
      state.loadError = true;
    }).then(function () {
      state.loading = false;
    });
  }

  // The events after `synced`, a page at a time, until a short page. `synced` moves only when a page arrived, so a
  // failed fetch leaves it where it was and the next confirmation asks again from there. (The newest event of the feed
  // is no good for this: an event of the cable moves it past a hole.)
  function catchUp() {
    return retried(function () { return getJSON(events + PAGE + "&after=" + synced); }).then(function (answer) {
      merge(answer.events);
      if (answer.events.length > 0) {
        synced = Math.max(synced, answer.last_event_id);
      }
      if (answer.events.length === PAGE) {
        return catchUp();
      }
    });
  }

  // A card that an event names flashes once; a counter lets the same card flash again on the next event.
  function flash(id) {
    state.flash[id] = (state.flash[id] || 0) + 1;
    var count = state.flash[id];
    setTimeout(function () {
      if (state.flash[id] === count) {
        delete state.flash[id];
      }
    }, FLASH_MS);
  }

  function onEvent(message) {
    merge([{
      id: message.event_id,
      kind: message.type,
      card_id: message.card_id,
      actor: message.actor,
      data: message.data,
      created_at: message.at,
    }]);
    if (message.card_id !== null) {
      flash(message.card_id);
      listener(message.card_id);
    }
    if (timer === null) {
      timer = setTimeout(load, REFETCH_MS);
    }
  }

  // Every confirmation, the first too, fetches again: an event that came between the first fetch and the
  // confirmation was not broadcast to this client.
  function onSubscribed() {
    load();
    listener(null);
    catchUp().catch(function () {});
  }

  // The reload button: the board, the open card and the feed again at once, whatever the cable did. `refreshing` shows
  // that it runs.
  function reload() {
    if (state.refreshing) {
      return Promise.resolve();
    }
    state.refreshing = true;
    listener(null);
    return Promise.all([load(), catchUp().catch(function () {})]).then(function () {
      state.refreshing = false;
    });
  }

  // The tab is back (it was hidden, or the page came from the back/forward cache, or the window got the focus): its
  // timers were throttled and its socket may have died, so it reconnects a bad socket (the confirmation then fetches
  // everything, see onSubscribed) and otherwise fetches at once. The three events fire together, so only the first
  // one in WAKE_MS counts.
  var woke = 0;
  var cable = null;
  function wake() {
    if (document.visibilityState === "hidden" || Date.now() - woke < WAKE_MS || !cable) {
      return;
    }
    woke = Date.now();
    if (!cable.check()) {
      reload();
    }
  }
  document.addEventListener("visibilitychange", wake);
  window.addEventListener("pageshow", wake);
  window.addEventListener("focus", wake);

  loadOlder(NEWEST).then(function () {
    synced = state.feed.length ? state.feed[0].id : 0;
    return load();
  }).then(function () {
    cable = subscribe({ channel: "BoardChannel", board: slug }, onEvent, onSubscribed);
  }, function (error) {
    state.error = error.message;
  });

  return state;
}
