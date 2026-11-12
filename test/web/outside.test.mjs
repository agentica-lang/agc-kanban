// `make test` runs this with `node --test`: which clicks outside the open panel close it (the end of a text selection is left out by the caller).
import assert from "node:assert/strict";
import { test } from "node:test";
import { closesPanel } from "../../app/javascript/outside.js";

// A stand-in for the path of an event: one node that `matches` the selectors of `inside`, as an ancestor would.
function at(inside) {
  return [{
    matches: function (selector) {
      return selector.split(",").some(function (one) { return inside.indexOf(one.trim()) !== -1; });
    },
  }];
}

var plain = { button: 0, ctrlKey: false, metaKey: false, shiftKey: false, altKey: false };

function click(path, extra) {
  return Object.assign({ path: path }, plain, extra || {});
}

test("a plain click on the board around the panel closes it", function () {
  assert.equal(closesPanel(click(at([".board"]))), true);
  assert.equal(closesPanel(click(at([]))), true);
});

test("a click that has its own job keeps the panel: in it, on a card, in the header, on the filter bar, on the backdrop", function () {
  ["#drawer", ".card", ".top", ".logout", ".filters", ".filters-none", ".backdrop"].forEach(function (place) {
    assert.equal(closesPanel(click(at([place]))), false, place);
  });
});

test("other buttons and modifier clicks keep it", function () {
  assert.equal(closesPanel(click([])), true);
  assert.equal(closesPanel(click(at([".board"]), { button: 1 })), false);
  assert.equal(closesPanel(click(at([".board"]), { metaKey: true })), false);
});
