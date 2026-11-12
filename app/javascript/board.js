import { getJSON, h } from "./api.js";
import { subscribe } from "./cable.js";
import { render } from "./render.js";

var REFETCH_MS = 80; // a burst of events (a claim and a move) is one fetch
var RETRY_MS = 2000; // the pause before the one retry of a failed feed fetch
var PAGE = 30; // events shown at first, and loaded by each "Ver más"
var NEWEST = Number.MAX_SAFE_INTEGER; // `before` of the newest page

// The board page: the snapshot of the API drawn by `render`, fetched again after each event the cable brings and after
// each confirmed subscription, so a missed broadcast never leaves a wrong board.
//
// The feed is the events by id, newest first, with no duplicates (an event can come from the cable and from a fetch).
// The last PAGE events load first, `before` the oldest shown gives the older ones, and what happened since the newest
// one seen is read forward with `after`.
export function startBoard(root, slug) {
  var events = "/api/boards/" + encodeURIComponent(slug) + "/events?limit=";
  var state = { board: null, cards: [], feed: [], changed: {}, more: false, loadMore: loadMore };
  var timer = null;

  function draw() {
    render(root, state);
    state.changed = {};
  }

  function newest() {
    return state.feed.length ? state.feed[0].id : 0;
  }

  function oldest() {
    return state.feed[state.feed.length - 1].id;
  }

  function merge(list) {
    var byId = {};
    state.feed.concat(list).forEach(function (event) { byId[event.id] = event; });
    state.feed = Object.keys(byId).map(function (id) { return byId[id]; }).sort(function (a, b) { return b.id - a.id; });
  }

  function showError(error) {
    root.replaceChildren(h("main", null, h("h1", null, "Board " + slug), h("p", { class: "empty" }, error.message)));
  }

  function load() {
    timer = null;
    return getJSON("/api/boards/" + encodeURIComponent(slug)).then(function (snapshot) {
      state.board = snapshot.board;
      state.cards = snapshot.cards;
      draw();
    }, showError);
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
    retried(function () { return loadOlder(oldest()); }).then(draw, function () {});
  }

  // The events after `last`, a page at a time, until a short page. A page is merged only when it arrived, so `last`
  // (the newest event seen) stays where it was until a fetch succeeds, and the next confirmation asks again from it.
  function catchUp(last) {
    return retried(function () { return getJSON(events + PAGE + "&after=" + last); }).then(function (answer) {
      merge(answer.events);
      if (answer.events.length === PAGE) {
        return catchUp(answer.last_event_id);
      }
    });
  }

  function onEvent(message) {
    merge([{ id: message.event_id, kind: message.type, card_id: message.card_id, actor: message.actor }]);
    if (message.card_id !== null) {
      state.changed[message.card_id] = true;
    }
    if (timer === null) {
      timer = setTimeout(load, REFETCH_MS);
    }
  }

  // Every confirmation, the first too, fetches again: an event that came between the first fetch and the
  // confirmation was not broadcast to this client. `after` is read now, before any event of the cable is handled.
  function onSubscribed() {
    var last = newest();
    load();
    catchUp(last).then(draw, function () {});
  }

  loadOlder(NEWEST).then(function () {
    return load();
  }).then(function () {
    subscribe({ channel: "BoardChannel", board: slug }, onEvent, onSubscribed);
  }, showError);
}
