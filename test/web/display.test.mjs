// `make test` runs this with `node --test`: the display settings of the board page, kept per board in the viewer's
// localStorage, and the preview line of a body.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEFAULTS, preview, readDisplay, useDisplay, writeDisplay } from "../../app/javascript/display.js";

function memory() {
  var map = new Map();
  return {
    map: map,
    getItem: function (key) { return map.has(key) ? map.get(key) : null; },
    setItem: function (key, value) { map.set(key, String(value)); },
    removeItem: function (key) { map.delete(key); },
  };
}

function useStorage(store) {
  Object.defineProperty(globalThis, "localStorage", { value: store, configurable: true, writable: true });
}

afterEach(function () { delete globalThis.localStorage; });

test("the defaults are what a card shows today plus the relation chips", function () {
  assert.deepEqual(DEFAULTS, { relations: true, lines: false, labels: true, agent: true, links: false, time: false, body: false });
  assert.deepEqual(readDisplay(memory(), "p"), DEFAULTS);
});

test("what is written reads back the same, per board; only what differs from the defaults is kept", function () {
  var store = memory();
  var settings = Object.assign({}, DEFAULTS, { lines: true, labels: false });
  writeDisplay(store, "p", settings);
  assert.deepEqual(JSON.parse(store.getItem("agc-kanban.display.p")), { lines: true, labels: false });
  assert.deepEqual(readDisplay(store, "p"), settings);
  assert.deepEqual(readDisplay(store, "other"), DEFAULTS, "another board keeps its own");
  writeDisplay(store, "p", DEFAULTS);
  assert.equal(store.getItem("agc-kanban.display.p"), null, "the defaults leave no key");
});

test("a broken or foreign value, a throwing storage and no storage read as the defaults, key by key", function () {
  var store = memory();
  ["not json", "[1]", "\"x\"", "null", "3"].forEach(function (value) {
    store.setItem("agc-kanban.display.p", value);
    assert.deepEqual(readDisplay(store, "p"), DEFAULTS, value);
  });
  store.setItem("agc-kanban.display.p", JSON.stringify({ lines: true, labels: "no", agent: 0, unknown: true, time: true }));
  assert.deepEqual(readDisplay(store, "p"), Object.assign({}, DEFAULTS, { lines: true, time: true }), "a value that is not a boolean has its default");
  var throwing = { getItem: function () { throw new Error("denied"); }, setItem: function () { throw new Error("denied"); }, removeItem: function () { throw new Error("denied"); } };
  assert.deepEqual(readDisplay(throwing, "p"), DEFAULTS);
  assert.doesNotThrow(function () { writeDisplay(throwing, "p", Object.assign({}, DEFAULTS, { lines: true })); });
  assert.deepEqual(readDisplay(null, "p"), DEFAULTS);
});

test("a setting changes at once, survives a reload of the page, and a reset goes back to the defaults; without storage it still changes", function () {
  var store = memory();
  useStorage(store);
  var page = useDisplay("p");
  assert.equal(page.isDefault(), true);
  page.set("lines", true);
  page.set("relations", false);
  page.set("nonsense", true);
  assert.equal(page.settings.lines, true);
  assert.equal("nonsense" in page.settings, false, "only the known settings");
  assert.equal(useDisplay("p").settings.lines, true, "kept for the next load");
  assert.equal(useDisplay("p").settings.relations, false);
  assert.equal(useDisplay("other").settings.lines, false, "per board");
  page.reset();
  assert.deepEqual(Object.assign({}, page.settings), DEFAULTS);
  assert.equal(store.getItem("agc-kanban.display.p"), null);
  delete globalThis.localStorage;
  var bare = useDisplay("p");
  bare.set("body", true);
  assert.equal(bare.settings.body, true);
});

test("the preview is the first line that says something, as plain text, cut short", function () {
  assert.equal(preview(""), "");
  assert.equal(preview(null), "");
  assert.equal(preview("\n\n  First line  \nsecond"), "First line");
  assert.equal(preview("## Heading\nbody"), "Heading");
  assert.equal(preview("> quoted **bold** and `code`"), "quoted bold and code");
  assert.equal(preview("- item one\n- item two"), "item one");
  assert.equal(preview("```js\nx\n```"), "x", "the fence line is no text");
  assert.equal(preview("see [the docs](https://x.test/a_b) now"), "see the docs now");
  assert.equal(preview("---\nreal"), "real");
  var long = preview("word ".repeat(100));
  assert.ok(long.length <= 120 && long.endsWith("…"), long);
});
