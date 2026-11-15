// `make test` runs this with `node --test`: the collapsed columns of the board page, kept per board in the viewer's
// localStorage, and a page that still works when the storage throws or holds something else.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { readCollapsed, useCollapsed, writeCollapsed } from "../../app/javascript/collapse.js";

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

test("what is written reads back the same, per board, and nothing collapsed leaves no key", function () {
  var store = memory();
  writeCollapsed(store, "p", [3, 1]);
  writeCollapsed(store, "other", [7]);
  assert.deepEqual(readCollapsed(store, "p"), [3, 1]);
  assert.deepEqual(readCollapsed(store, "other"), [7]);
  writeCollapsed(store, "p", readCollapsed(store, "p"));
  assert.deepEqual(readCollapsed(store, "p"), [3, 1]);
  writeCollapsed(store, "p", []);
  assert.equal(store.getItem("agc-kanban.collapsed.p"), null);
  assert.deepEqual(readCollapsed(store, "p"), []);
});

test("a broken or foreign value, a throwing storage and no storage read as nothing collapsed", function () {
  var store = memory();
  ["not json", "{\"a\":1}", "\"3\"", "null"].forEach(function (value) {
    store.setItem("agc-kanban.collapsed.p", value);
    assert.deepEqual(readCollapsed(store, "p"), [], value);
  });
  store.setItem("agc-kanban.collapsed.p", "[1,\"2\",null,4.5,5]");
  assert.deepEqual(readCollapsed(store, "p"), [1, 5]);
  var throwing = { getItem: function () { throw new Error("denied"); }, setItem: function () { throw new Error("denied"); }, removeItem: function () { throw new Error("denied"); } };
  assert.deepEqual(readCollapsed(throwing, "p"), []);
  assert.doesNotThrow(function () { writeCollapsed(throwing, "p", [1]); });
  assert.deepEqual(readCollapsed(null, "p"), []);
});

test("a toggle collapses and expands a column and survives a reload of the page; without storage it still toggles", function () {
  var store = memory();
  useStorage(store);
  var page = useCollapsed("p");
  page.toggle(2);
  page.toggle(4);
  assert.equal(page.has(2), true);
  var reloaded = useCollapsed("p");
  assert.equal(reloaded.has(2) && reloaded.has(4), true);
  assert.equal(useCollapsed("other").has(2), false, "another board keeps its own columns");
  reloaded.toggle(2);
  assert.deepEqual([useCollapsed("p").has(2), useCollapsed("p").has(4)], [false, true]);

  useStorage({ getItem: function () { throw new Error("denied"); }, setItem: function () { throw new Error("denied"); } });
  var bare = useCollapsed("p");
  bare.toggle(9);
  assert.equal(bare.has(9), true);
  delete globalThis.localStorage;
  var none = useCollapsed("p");
  none.toggle(9);
  assert.equal(none.has(9), true);
});
