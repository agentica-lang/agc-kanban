// `make test` runs this with `node --test`: opening a card is a step in the browser history, so Back and Forward walk
// through the cards opened and the board, and the filters stay. The browser's session history is played by a small
// model (entries, a position, `popstate` on Back and Forward) behind the globals that the page code reads.
import assert from "node:assert/strict";
import { test } from "node:test";
import { createApp, effectScope, reactive } from "vue";
import { plainClick, useDrawer } from "../../app/javascript/drawer.js";
import { followDrawer, useCard } from "../../app/javascript/card_store.js";
import { useFilters } from "../../app/javascript/filter_store.js";
import { Markdown } from "../../app/javascript/markdown.js";

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
    get search() {
      var mark = entries[at].indexOf("?");
      return mark < 0 ? "" : entries[at].slice(mark);
    },
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
  return { tab: tab, drawer: made.drawer, filter: made.filter, scope: scope, stop: function () { scope.stop(); } };
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

test("a ?card= that does not exist closes the panel quietly: no new entry, and Back skips it", function () {
  var one = page("/boards/p?label=api");
  one.drawer.showCard(1);
  one.drawer.showCard(99);
  var length = one.tab.length();
  one.drawer.dismiss(98); // an answer for a card that is no longer the open one changes nothing
  assert.equal(one.drawer.card.value, 99);
  one.drawer.dismiss(99);
  assert.equal(one.drawer.card.value, null);
  assert.equal(one.drawer.panel.value, "");
  assert.equal(one.tab.length(), length);
  assert.equal(one.tab.url().has("card"), false);
  assert.equal(one.tab.url().get("label"), "api");
  one.tab.back();
  assert.equal(one.drawer.card.value, 1);
  one.stop();
  var direct = page("/boards/p?card=404&label=api");
  direct.drawer.dismiss(404);
  assert.equal(direct.drawer.panel.value, "");
  assert.equal(direct.tab.length(), 1);
  assert.equal(direct.tab.url().get("label"), "api");
  direct.stop();
});

test("the card store says a 404 is a card that is gone, and any other failure is not", async function () {
  var scope = effectScope();
  var store = scope.run(useCard);
  var status = 404;
  globalThis.fetch = function () { return Promise.resolve({ ok: false, status: status, json: function () { return {}; } }); };
  store.show(404);
  await new Promise(function (resolve) { setTimeout(resolve, 10); });
  assert.equal(store.gone, true);
  status = 500;
  store.show(5);
  assert.equal(store.gone, false);
  await new Promise(function (resolve) { setTimeout(resolve, 10); });
  assert.equal(store.gone, false);
  assert.match(store.error, /500/);
  scope.stop();
});

// The click handler that a Markdown text puts on its root, with `openCard` provided as the board page does.
function markdownClick(board, opened) {
  var render = null;
  createApp({}).provide("openCard", function (id) { opened.push(id); }).runWithContext(function () {
    render = Markdown.setup(reactive({ text: "x", board: board }));
  });
  var handler = render().props.onClick;
  return function (href, init) {
    var event = Object.assign({ button: 0, metaKey: false, ctrlKey: false, shiftKey: false, altKey: false, prevented: false,
      preventDefault: function () { this.prevented = true; } }, init);
    // `href` null is a click that is not on a link (`closest` finds none); `text` is a click on a text node, which is no Element.
    event.target = init && init.text ? {} : Object.assign(new Element(), { closest: function () { return href === null ? null : { href: href }; } });
    handler(event);
    return event;
  };
}

test("a plain click on a Markdown link to a card of this board opens it in the panel; a modified click or another link does not", function () {
  globalThis.Element = class {};
  globalThis.location = { origin: "http://kanban.test" };
  var opened = [];
  var click = markdownClick("p", opened);
  assert.equal(click("http://kanban.test/boards/p?card=12").prevented, true);
  assert.deepEqual(opened, [12]);
  [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { button: 1 }].forEach(function (init) {
    assert.equal(click("http://kanban.test/boards/p?card=13", init).prevented, false);
  });
  assert.equal(click("http://kanban.test/boards/other?card=14").prevented, false);
  assert.equal(click("https://example.com/boards/p?card=15").prevented, false);
  assert.deepEqual(opened, [12]);
});

test("a click in a Markdown text that is not on a link is left alone, even beside a card link", function () {
  globalThis.Element = class {};
  globalThis.location = { origin: "http://kanban.test" };
  var opened = [];
  var click = markdownClick("p", opened);
  assert.equal(click(null).prevented, false);
  assert.equal(click("http://kanban.test/boards/p?card=12", { text: true }).prevented, false);
  assert.deepEqual(opened, []);
});

test("a card that is gone closes the panel through the board page's wiring: the 404 clears `card` from the URL", async function () {
  var one = page("/boards/p?label=api&card=404");
  var seen = null;
  globalThis.fetch = function (url) {
    seen = url;
    return Promise.resolve({ ok: false, status: 404, json: function () { return {}; } });
  };
  var card = one.scope.run(useCard);
  one.scope.run(function () { followDrawer(one.drawer, card); });
  await new Promise(function (resolve) { setTimeout(resolve, 20); });
  assert.match(seen, /\/api\/cards\/404$/);
  assert.equal(one.drawer.card.value, null);
  assert.equal(one.drawer.panel.value, "");
  assert.equal(one.tab.url().has("card"), false);
  assert.equal(one.tab.url().get("label"), "api");
  assert.equal(one.tab.length(), 1);
  one.stop();
});

test("after the page's scope stops, a drawer change fetches nothing", async function () {
  var one = page("/boards/p");
  var fetched = [];
  globalThis.fetch = function (url) {
    fetched.push(url);
    return Promise.resolve({ ok: true, status: 200, json: function () { return { card: { id: 0 }, comments: [] }; } });
  };
  var card = one.scope.run(useCard);
  one.scope.run(function () { followDrawer(one.drawer, card); });
  one.drawer.showCard(4);
  await new Promise(function (resolve) { setTimeout(resolve, 20); });
  assert.equal(fetched.length, 1, "the live page follows the drawer");
  assert.match(fetched[0], /\/api\/cards\/4$/);
  one.stop();
  one.drawer.showCard(5);
  await new Promise(function (resolve) { setTimeout(resolve, 20); });
  assert.equal(fetched.length, 1, "a stopped page fetches nothing");
});

test("the archive panel opens and closes, and a card opened from it goes back to it when closed", function () {
  var one = page("/boards/p");
  one.drawer.toggleArchive();
  assert.equal(one.drawer.panel.value, "archive");
  one.drawer.showCard(4);
  assert.equal(one.drawer.panel.value, "card");
  one.drawer.close();
  assert.equal(one.drawer.panel.value, "archive");
  one.drawer.toggleFilters();
  assert.equal(one.drawer.panel.value, "filters");
  one.drawer.toggleArchive();
  assert.equal(one.drawer.panel.value, "archive");
  one.drawer.close();
  assert.equal(one.drawer.panel.value, "");
  one.stop();
});

test("the display panel opens and closes, replaces the other panels, and a card opened from it goes back to it when closed", function () {
  var one = page("/boards/p");
  one.drawer.toggleDisplay();
  assert.equal(one.drawer.panel.value, "display");
  one.drawer.showCard(4);
  assert.equal(one.drawer.panel.value, "card");
  one.drawer.close();
  assert.equal(one.drawer.panel.value, "display");
  one.drawer.toggleFilters();
  assert.equal(one.drawer.panel.value, "filters");
  one.drawer.toggleDisplay();
  assert.equal(one.drawer.panel.value, "display");
  one.drawer.toggleArchive();
  assert.equal(one.drawer.panel.value, "archive");
  one.drawer.toggleDisplay();
  one.drawer.toggleActivity();
  assert.equal(one.drawer.panel.value, "activity");
  one.drawer.toggleDisplay();
  assert.equal(one.drawer.panel.value, "display");
  one.drawer.toggleDisplay();
  assert.equal(one.drawer.panel.value, "activity", "the gear again closes it, and the activity under it shows again, as for the filters");
  one.stop();
});
