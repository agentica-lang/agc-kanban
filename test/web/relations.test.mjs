// `make test` runs this with `node --test`: the relations between the cards of a board and the line that joins two cards.
import assert from "node:assert/strict";
import { test } from "node:test";
import { curve, dependency, indexOf, mark, pairs, related, visible } from "../../app/javascript/relations.js";

function card(id, depends_on, blocks, extra) {
  return Object.assign({ id: id, depends_on: depends_on || [], blocks: blocks || [], done: false, column: "Todo" }, extra);
}

test("a dependency says whether it is done and where it is; one that is not on the board does not block", function () {
  var byId = indexOf([card(1, [], [], { done: true, column: "Done" }), card(2, [], [], { column: "Doing" })]);
  assert.deepEqual(dependency(byId, 1), { id: 1, known: true, done: true, column: "Done" });
  assert.deepEqual(dependency(byId, 2), { id: 2, known: true, done: false, column: "Doing" });
  assert.deepEqual(dependency(byId, 9), { id: 9, known: false, done: true, column: "" });
});

test("the related cards of a card are the ones it depends on and the ones that depend on it, each once, never itself", function () {
  assert.deepEqual(related(card(5, [1, 2], [3, 2, 5])), [1, 2, 3]);
  assert.deepEqual(related(card(5)), []);
  assert.deepEqual(related({ id: 5 }), [], "a card with no lists");
});

test("each pair is listed once, from the needed card to the card that needs it, when both are on the board", function () {
  var cards = [card(1, [], [2, 3]), card(2, [1], [3]), card(3, [1, 2, 8]), card(4, [], [9])];
  assert.deepEqual(pairs(cards), [{ from: 1, to: 2 }, { from: 1, to: 3 }, { from: 2, to: 3 }]);
});

test("a hovered card is self and its relations are related; the rest are dim only for a pointer", function () {
  var byId = indexOf([card(1, [], [2]), card(2, [1]), card(3)]);
  assert.equal(mark(byId, 1, 1, true), "self");
  assert.equal(mark(byId, 1, 2, true), "related");
  assert.equal(mark(byId, 1, 3, true), "dim");
  assert.equal(mark(byId, 1, 3, false), "", "the keyboard focus dims nothing");
  assert.equal(mark(byId, 1, 2, false), "related");
  assert.equal(mark(byId, 2, 1, true), "related", "from either side");
  assert.equal(mark(byId, null, 1, true), "");
  assert.equal(mark(byId, 99, 1, true), "", "a hot card that is gone marks nothing");
});

test("a hot card with no related card marks and dims nothing", function () {
  var byId = indexOf([card(1), card(2), card(3)]);
  [1, 2, 3].forEach(function (id) { assert.equal(mark(byId, 1, id, true), ""); });
});

test("the line leaves the side that faces the other card, and two cards in one column are joined on their right sides", function () {
  var left = { left: 0, right: 100, top: 0, bottom: 40 };
  var right = { left: 300, right: 400, top: 100, bottom: 140 };
  assert.equal(curve(left, right), "M100 20 C200 20 200 120 300 120");
  assert.equal(curve(right, left), "M300 120 C200 120 200 20 100 20");
  var below = { left: 0, right: 100, top: 100, bottom: 140 };
  assert.equal(curve(left, below), "M100 20 C128 20 128 120 100 120");
  var near = { left: 110, right: 210, top: 0, bottom: 40 };
  assert.equal(curve(left, near), "M100 20 C128 20 82 20 110 20", "a narrow gap still bulges a little");
});

test("a card is visible when its middle is inside the clip", function () {
  var clip = { left: 0, right: 100, top: 0, bottom: 100 };
  assert.equal(visible({ left: 10, right: 50, top: 10, bottom: 30 }, clip), true);
  assert.equal(visible({ left: 10, right: 50, top: 90, bottom: 130 }, clip), false, "scrolled half out: the middle is out");
  assert.equal(visible({ left: 10, right: 50, top: 70, bottom: 110 }, clip), true);
  assert.equal(visible({ left: 200, right: 240, top: 10, bottom: 30 }, clip), false);
});
