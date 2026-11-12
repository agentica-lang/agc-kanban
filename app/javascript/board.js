import { getJSON, h } from "./api.js";
import { subscribe } from "./cable.js";
import { render } from "./render.js";

var REFETCH_MS = 80; // a burst of events (a claim and a move) is one fetch
var FEED_SIZE = 12;

// The board page: the snapshot of the API drawn by `render`, fetched again after each event the cable brings and after
// each reconnect, so a missed broadcast never leaves a wrong board.
export function startBoard(root, slug) {
  var state = { board: null, cards: [], feed: [], changed: {} };
  var timer = null;

  function draw() {
    render(root, state);
    state.changed = {};
  }

  function load() {
    timer = null;
    return getJSON("/api/boards/" + encodeURIComponent(slug)).then(function (snapshot) {
      state.board = snapshot.board;
      state.cards = snapshot.cards;
      draw();
    }, function (error) {
      root.replaceChildren(h("main", null, h("h1", null, "Board " + slug), h("p", { class: "empty" }, error.message)));
    });
  }

  function onEvent(event) {
    state.feed = [event].concat(state.feed).slice(0, FEED_SIZE);
    if (event.card_id !== null) {
      state.changed[event.card_id] = true;
    }
    if (timer === null) {
      timer = setTimeout(load, REFETCH_MS);
    }
  }

  load().then(function () {
    subscribe({ channel: "BoardChannel", board: slug }, onEvent, function (again) {
      if (again) {
        load();
      }
    });
  });
}
