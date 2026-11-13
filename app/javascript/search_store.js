import { ref, watch } from "vue";
import { getJSON } from "./api.js";

var DEBOUNCE_MS = 150; // as-you-type: one request after a pause in the typing
var LIMIT = 100; // the most the server answers (its maximum)

// The search of the board page: the text lives in the URL (`?q=`, with the filters and `?card=`), and the server ranks
// the cards that match it (SQLite FTS5, best first). The board shows only those cards, in that order, together with the
// other filters. `ranks` maps a card id to its place in the answer, or is null while no answer has come, so the board
// keeps showing what it showed. `version` changes when the board is fetched again (a cable event, the reload button):
// the search runs again then, so a card edited or added by someone else enters or leaves the result.
export function useSearch(slug, version) {
  var q = ref(new URLSearchParams(location.search).get("q") || "");
  var ranks = ref(null);
  var failed = ref(false);
  var sent = 0;
  var timer = null;

  function write(text) {
    var url = new URL(location.href);
    if (text === "") {
      url.searchParams.delete("q");
    } else {
      url.searchParams.set("q", text);
    }
    history.replaceState(history.state, "", url);
  }

  function run() {
    timer = null;
    var mine = ++sent;
    var path = "/api/boards/" + encodeURIComponent(slug) + "/search?all=1&limit=" + LIMIT + "&q=" + encodeURIComponent(q.value);
    getJSON(path).then(function (answer) {
      if (mine === sent) {
        var map = {};
        answer.results.forEach(function (hit, index) { map[hit.card.id] = index; });
        ranks.value = map;
        failed.value = false;
      }
    }, function () {
      if (mine === sent) {
        failed.value = true;
      }
    });
  }

  // `set` is what the input calls on each keystroke.
  function set(text) {
    q.value = text;
    write(text);
    clearTimeout(timer);
    if (text.trim() === "") {
      sent += 1;
      ranks.value = null;
      failed.value = false;
    } else {
      timer = setTimeout(run, DEBOUNCE_MS);
    }
  }

  watch(version, function () {
    if (q.value.trim() !== "" && timer === null) {
      run();
    }
  });
  if (q.value.trim() !== "") {
    run();
  }

  return {
    q: q,
    failed: failed,
    set: set,
    clear: function () { set(""); },
    on: function () { return q.value.trim() !== ""; },
    // Whether `card` shows: all do without a query; with one, those in the answer.
    matches: function (card) { return ranks.value === null || ranks.value[card.id] !== undefined; },
    // The place of `card` in the answer, for the sort (a card the answer lacks goes last).
    rank: function (card) { return ranks.value === null || ranks.value[card.id] === undefined ? Infinity : ranks.value[card.id]; },
    count: function () { return ranks.value === null ? null : Object.keys(ranks.value).length; },
  };
}
