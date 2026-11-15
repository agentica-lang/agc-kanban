// `make test` runs this with `node --test`: a chip takes the viewer to its card (`reveal`), a collapsed column opens for
// the visit only, and the lines between cards listen to what moves them and let go when they are gone.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { useCollapsed } from "../../app/javascript/collapse.js";
import { watchLines } from "../../app/javascript/lines_watch.js";
import { reveal } from "../../app/javascript/reveal.js";

function memory() {
  var map = new Map();
  return {
    map: map,
    getItem: function (key) { return map.has(key) ? map.get(key) : null; },
    setItem: function (key, value) { map.set(key, String(value)); },
    removeItem: function (key) { map.delete(key); },
  };
}

afterEach(function () { delete globalThis.localStorage; });

// The page as `reveal` sees it: cards in columns, the links that are drawn, and what happens to the one that is found.
function page(drawn) {
  var calls = { scrolled: [], focused: [], opened: [], queries: [] };
  var queue = [];
  var collapsed = useCollapsed("p");
  var env = {
    cards: function () { return [{ id: 1, column_id: 10 }, { id: 2, column_id: 20 }]; },
    collapsed: collapsed,
    document: {
      querySelector: function (selector) {
        calls.queries.push(selector);
        var id = Number(/data-card="(\d+)"/.exec(selector)[1]);
        return drawn.includes(id) ? {
          scrollIntoView: function (options) { calls.scrolled.push([id, options]); },
          focus: function (options) { calls.focused.push([id, options]); },
        } : null;
      },
    },
    reduced: function () { return false; },
    open: function (id) { calls.opened.push(id); },
    later: function (fn) { queue.push(fn); },
  };
  return { env: env, calls: calls, collapsed: collapsed, render: function () { queue.splice(0).forEach(function (fn) { fn(); }); } };
}

test("a chip scrolls to the card and moves the focus to its title, without touching the scroll again", function () {
  var one = page([2]);
  reveal(one.env, 2);
  assert.deepEqual(one.calls.focused, [], "nothing before the render");
  one.render();
  assert.deepEqual(one.calls.scrolled, [[2, { block: "center", inline: "center", behavior: "smooth" }]]);
  assert.deepEqual(one.calls.focused, [[2, { preventScroll: true }]]);
  assert.deepEqual(one.calls.opened, []);
  assert.ok(one.calls.queries[0].includes('a.title[data-card="2"]'));
});

test("a viewer who asks for less motion gets no smooth scroll", function () {
  var one = page([2]);
  one.env.reduced = function () { return true; };
  reveal(one.env, 2);
  one.render();
  assert.equal(one.calls.scrolled[0][1].behavior, "auto");
});

test("a card that is not drawn (hidden by the filters, or gone from the board) opens in the panel", function () {
  var one = page([]);
  reveal(one.env, 2);
  reveal(one.env, 99);
  one.render();
  assert.deepEqual(one.calls.opened, [2, 99]);
  assert.deepEqual(one.calls.focused, []);
});

test("a card in a collapsed column opens that column for this visit and saves nothing", function () {
  var store = memory();
  Object.defineProperty(globalThis, "localStorage", { value: store, configurable: true, writable: true });
  var one = page([1]);
  one.collapsed.toggle(10);
  assert.equal(store.getItem("agc-kanban.collapsed.p"), "[10]");
  assert.equal(one.collapsed.has(10), true);
  reveal(one.env, 1);
  assert.equal(one.collapsed.has(10), false, "open for the visit");
  assert.equal(store.getItem("agc-kanban.collapsed.p"), "[10]", "still saved as collapsed");
  one.render();
  assert.deepEqual(one.calls.focused, [[1, { preventScroll: true }]]);
  assert.equal(useCollapsed("p").has(10), true, "the next load shows the strip again");
  one.collapsed.toggle(10);
  assert.equal(one.collapsed.has(10), true, "the button collapses it again with nothing to save");
  assert.equal(store.getItem("agc-kanban.collapsed.p"), "[10]");
  one.collapsed.toggle(10);
  assert.equal(one.collapsed.has(10), false, "the expand button of a strip is the viewer's choice, and is saved");
  assert.equal(store.getItem("agc-kanban.collapsed.p"), null);
});

test("revealing a column that is open changes nothing, and a column that goes away is forgotten", function () {
  var one = page([1]);
  one.collapsed.reveal(10);
  assert.equal(one.collapsed.has(10), false);
  one.collapsed.toggle(10);
  one.collapsed.reveal(10);
  one.collapsed.keep([20]);
  assert.equal(one.collapsed.has(10), false, "the saved id of a column that is gone is dropped, and the visit with it");
});

function fakeHost() {
  var added = [];
  var removed = [];
  return {
    added: added,
    removed: removed,
    addEventListener: function (name, fn, options) { added.push([name, fn, options]); },
    removeEventListener: function (name, fn, options) { removed.push([name, fn, options]); },
  };
}

function fakeObserver() {
  var seen = { observed: [], unobserved: [], disconnected: 0 };
  function Observer(callback) { seen.callback = callback; }
  Observer.prototype.observe = function (element) { seen.observed.push(element); };
  Observer.prototype.unobserve = function (element) { seen.unobserved.push(element); };
  Observer.prototype.disconnect = function () { seen.disconnected += 1; };
  return { Observer: Observer, seen: seen };
}

test("the lines listen to every scroll below the board, the resize and the size of the board and of the cards they join, and let go on stop", function () {
  var host = fakeHost();
  var win = fakeHost();
  var observer = fakeObserver();
  var schedule = function () {};
  var watcher = watchLines(host, schedule, win, observer.Observer);
  assert.deepEqual(host.added, [["scroll", schedule, { capture: true, passive: true }]]);
  assert.deepEqual(win.added, [["resize", schedule, undefined]]);
  assert.deepEqual(observer.seen.observed, [host], "the board itself");
  var a = {};
  var b = {};
  var c = {};
  watcher.sync([a, b]);
  watcher.sync([a, b]);
  assert.deepEqual(observer.seen.observed.slice(1), [a, b], "a card is observed once");
  watcher.sync([b, c]);
  assert.deepEqual(observer.seen.unobserved, [a], "a card that lost its lines is let go");
  assert.deepEqual(observer.seen.observed.slice(3), [c]);
  watcher.stop();
  assert.deepEqual(host.removed, [["scroll", schedule, { capture: true }]], "removed with the same capture flag");
  assert.deepEqual(win.removed, [["resize", schedule, undefined]]);
  assert.equal(observer.seen.disconnected, 1);
});

test("without ResizeObserver the lines still follow scroll and resize, and stop cleanly", function () {
  var host = fakeHost();
  var win = fakeHost();
  var watcher = watchLines(host, function () {}, win, undefined);
  assert.doesNotThrow(function () { watcher.sync([{}]); });
  watcher.stop();
  assert.equal(host.removed.length, 1);
  assert.equal(win.removed.length, 1);
});
