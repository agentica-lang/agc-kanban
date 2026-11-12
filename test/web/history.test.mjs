// `make test` runs this with `node --test`: opening a card is a step in the browser history, so Back and Forward walk
// through the cards opened and the board, and the filters stay. The browser's session history is played by a small
// model (entries, a position, `popstate` on Back and Forward) behind the globals that the page code reads.
import assert from "node:assert/strict";
import { test } from "node:test";
import { effectScope } from "vue";
import { plainClick, useDrawer } from "../../app/javascript/drawer.js";
import { useFilters } from "../../app/javascript/filter_store.js";

function browser(start) {
  var entries = [start];
  var at = 0;
  var listeners = [];
  var move = function (to) {
    if (to >= 0 && to < entries.length) {
      at = to;
      listeners.forEach(function (listener) { listener(); });
    }
  };
  globalThis.window = {
    addEventListener: function (name, listener) { listeners.push(listener); },
    removeEventListener: function (name, listener) { listeners = listeners.filter(function (one) { return one !== listener; }); },
  };
  globalThis.location = {
    get href() { return "http://kanban.test" + entries[at]; },
    get search() { return entries[at].slice(entries[at].indexOf("?")); },
  };
  globalThis.history = {
    state: null,
    pushState: function (state, title, url) {
      entries = entries.slice(0, at + 1).concat([new URL(url).pathname + new URL(url).search]);
      at += 1;
    },
    replaceState: function (state, title, url) { entries[at] = new URL(url).pathname + new URL(url).search; },
  };
  return {
    back: function () { move(at - 1); },
    forward: function () { move(at + 1); },
    url: function () { return new URLSearchParams(location.search); },
    length: function () { return entries.length; },
  };
}

// The page: a drawer and its filters, made in a scope as the board page makes them.
function page(start) {
  var tab = browser(start);
  var scope = effectScope();
  var made = scope.run(function () { return { drawer: useDrawer(), filter: useFilters() }; });
  return { tab: tab, drawer: made.drawer, filter: made.filter, stop: function () { scope.stop(); } };
}

test("Back goes from a card to the card before it, then to the board with no panel, and Forward opens it again", function () {
  var one = page("/boards/p?label=api");
  one.drawer.showCard(1);
  one.drawer.showCard(2);
  assert.equal(one.drawer.card.value, 2);
  assert.equal(one.tab.url().get("card"), "2");
  one.tab.back();
  assert.equal(one.drawer.card.value, 1);
  assert.equal(one.drawer.panel.value, "card");
  one.tab.back();
  assert.equal(one.drawer.card.value, null);
  assert.equal(one.drawer.panel.value, "");
  assert.equal(one.tab.url().has("card"), false);
  one.tab.forward();
  assert.equal(one.drawer.card.value, 1);
  one.tab.forward();
  assert.equal(one.drawer.card.value, 2);
  one.stop();
});

test("a direct load of ?card=N shows the panel at once and adds no history entry", function () {
  var one = page("/boards/p?card=7");
  assert.equal(one.drawer.card.value, 7);
  assert.equal(one.drawer.panel.value, "card");
  assert.equal(one.tab.length(), 1);
  one.stop();
});

test("closing the panel is a step too: Back after it reopens the card, and a second open of the same card adds none", function () {
  var one = page("/boards/p");
  one.drawer.showCard(3);
  one.drawer.showCard(3);
  assert.equal(one.tab.length(), 2);
  one.drawer.close();
  assert.equal(one.drawer.card.value, null);
  assert.equal(one.tab.url().has("card"), false);
  one.drawer.close();
  assert.equal(one.tab.length(), 3);
  one.tab.back();
  assert.equal(one.drawer.card.value, 3);
  assert.equal(one.tab.url().get("card"), "3");
  one.stop();
});

test("the filters survive opening, closing, Back and Forward, in the page and in the URL", function () {
  var one = page("/boards/p?label=api");
  one.drawer.showCard(1);
  one.filter.claimer("line 1");
  one.drawer.showCard(2);
  assert.equal(one.tab.url().get("claimer"), "line 1");
  assert.equal(one.tab.url().get("label"), "api");
  one.tab.back();
  one.tab.back();
  assert.equal(one.drawer.card.value, null);
  assert.deepEqual(one.filter.filters.value, { labels: ["api"], claimer: "line 1", ready: false });
  assert.equal(one.tab.url().get("claimer"), "line 1");
  one.tab.forward();
  one.tab.forward();
  assert.equal(one.drawer.card.value, 2);
  assert.deepEqual(one.filter.filters.value, { labels: ["api"], claimer: "line 1", ready: false });
  assert.equal(one.tab.length(), 3);
  one.filter.ready();
  assert.equal(one.tab.length(), 3);
  assert.equal(one.tab.url().get("ready"), "1");
  one.stop();
});

test("a plain left click on a link is the page's; a modifier or the middle button is the browser's (a new tab)", function () {
  assert.equal(plainClick({ button: 0, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false }), true);
  assert.equal(plainClick({ button: 1, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false }), false);
  ["metaKey", "ctrlKey", "shiftKey", "altKey"].forEach(function (key) {
    assert.equal(plainClick(Object.assign({ button: 0, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false }, { [key]: true })), false);
  });
});
