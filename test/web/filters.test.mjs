// `make test` runs this with `node --test`: the filters of the board view, from the URL and back.
import assert from "node:assert/strict";
import { test } from "node:test";
import { active, activeChips, cardSearch, count, matches, options, parse, search, toggleClaimer, toggleLabel, toggleReady, NO_FILTERS } from "../../app/javascript/filters.js";

function card(extra) {
  return Object.assign({ id: 1, labels: [], claimed_by: null, ready: true }, extra);
}

test("the URL reads as the filters and the filters write back to the same URL, with the other parameters kept", function () {
  var tricky = ["two words", "a&b", "100%", "café", "+plus", "0.8.0"];
  var filters = { labels: tricky, claimer: "line 1&2", ready: true };
  var written = search("?card=12", filters);
  assert.ok(written.startsWith("?card=12&label=two%20words,a%26b,"));
  assert.deepEqual(parse(written), filters);
  assert.equal(new URLSearchParams(written).get("card"), "12");
  assert.equal(search(written, NO_FILTERS), "?card=12");
  assert.equal(search("", NO_FILTERS), "");
});

test("a hand-written URL: a plain list, repeated labels, empty parts and a ready that is not 1", function () {
  assert.deepEqual(parse("?label=cc,0.8.0&claimer=line1&ready=1"), { labels: ["cc", "0.8.0"], claimer: "line1", ready: true });
  assert.deepEqual(parse("?label=a&label=b,,a&ready=true"), { labels: ["a", "b"], claimer: "", ready: false });
  assert.deepEqual(parse(""), NO_FILTERS);
});

test("a card shows with all the selected labels, the selected agent and, when asked, only when ready", function () {
  var one = card({ labels: ["cchecker", "0.8.0", "api"], claimed_by: "line1", ready: false });
  assert.equal(matches(one, { labels: ["cchecker", "0.8.0"], claimer: "", ready: false }), true);
  assert.equal(matches(one, { labels: ["cchecker", "0.9.0"], claimer: "", ready: false }), false);
  assert.equal(matches(one, { labels: [], claimer: "line1", ready: false }), true);
  assert.equal(matches(one, { labels: [], claimer: "line2", ready: false }), false);
  assert.equal(matches(one, { labels: [], claimer: "", ready: true }), false);
  assert.equal(matches(card(), { labels: [], claimer: "", ready: true }), true);
  assert.equal(matches(card(), { labels: ["x"], claimer: "", ready: false }), false);
  assert.equal(matches(card({ claimed_by: null }), { labels: [], claimer: "line1", ready: false }), false);
});

test("the chips come from the cards, keep a selected one no card has, and skip a label with a comma", function () {
  var cards = [card({ labels: ["b", "a", "x,y"], claimed_by: "z" }), card({ labels: ["a"], claimed_by: "m" })];
  assert.deepEqual(options(cards, NO_FILTERS), { labels: ["a", "b"], claimers: ["m", "z"] });
  assert.deepEqual(options(cards, { labels: ["gone"], claimer: "away", ready: false }), { labels: ["a", "b", "gone"], claimers: ["away", "m", "z"] });
});

test("toggles turn one filter on and off and leave the rest", function () {
  var on = toggleReady(toggleClaimer(toggleLabel(NO_FILTERS, "a"), "line1"));
  assert.deepEqual(on, { labels: ["a"], claimer: "line1", ready: true });
  assert.equal(active(on), true);
  assert.deepEqual(toggleLabel(toggleLabel(on, "b"), "a").labels, ["b"]);
  assert.equal(toggleClaimer(toggleClaimer(NO_FILTERS, "x"), "x").claimer, "");
  assert.equal(active(toggleReady(on)), true);
  assert.equal(active(NO_FILTERS), false);
});

test("the URL as the drawer rewrites it (URLSearchParams: + for a space, the commas escaped) reads the same", function () {
  assert.deepEqual(parse("?card=3&label=two+words%2Ca%26b%2C%2Bplus").labels, ["two words", "a&b", "+plus"]);
});

test("the active filters: their count for the button and one chip each to take it off, in a fixed order", function () {
  var on = { labels: ["b", "a"], claimer: "line1", ready: true };
  assert.equal(count(on), 4);
  assert.equal(count(NO_FILTERS), 0);
  assert.deepEqual(activeChips(on), [
    { kind: "ready", name: "", text: "Ready" },
    { kind: "claimer", name: "line1", text: "Agent: line1" },
    { kind: "label", name: "b", text: "b" },
    { kind: "label", name: "a", text: "a" },
  ]);
  assert.deepEqual(activeChips(NO_FILTERS), []);
});

test("the link of a card keeps the filters, so a new tab opens the same view", function () {
  assert.equal(cardSearch({ labels: ["a b"], claimer: "", ready: true }, 3), "?card=3&label=a%20b&ready=1");
  assert.equal(cardSearch(NO_FILTERS, 3), "?card=3");
});
