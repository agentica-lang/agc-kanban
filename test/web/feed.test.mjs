// `make test` runs this with `node --test`: the sentences of the activity feed, from the event data the server writes.
import assert from "node:assert/strict";
import { test } from "node:test";
import { byDay, entry, relative } from "../../app/javascript/feed.js";

var HOUR = 3600000;

function moved(extra) {
  return Object.assign({
    id: 7,
    kind: "card.moved",
    card_id: 12,
    actor: "line1",
    created_at: 1000,
    data: { card: { id: 12, title: "Fix login", column: "Review", column_id: 3, done: false }, forced: false },
  }, extra);
}

test("a move names the column it left and the one it reached", function () {
  var event = moved();
  event.data.from = { id: 2, name: "Doing" };
  var one = entry(event, {});
  assert.deepEqual([one.actor, one.verb, one.card, one.title, one.from, one.to, one.group], ["line1", "moved", 12, "Fix login", "Doing", "Review", "move"]);
});

test("an older move without the source shows the target only", function () {
  var one = entry(moved(), {});
  assert.deepEqual([one.from, one.to], ["", "Review"]);
});

test("the board's title wins, the event's is the fallback for a card gone since, and a long one is cut", function () {
  assert.equal(entry(moved(), { 12: "Renamed" }).title, "Renamed");
  assert.equal(entry(moved(), {}).title, "Fix login");
  var long = entry(moved(), { 12: "x".repeat(500) }).title;
  assert.equal(Array.from(long).length, 60);
  assert.ok(long.endsWith("…"));
});

test("a comment shows a one-line excerpt and the title from the board", function () {
  var event = { id: 8, kind: "comment.added", card_id: 24, actor: "kanban", created_at: 1000, data: { body: "PR #15\n\nopened " + "y".repeat(200) } };
  var one = entry(event, { 24: "Feed" });
  assert.equal(one.verb, "commented on");
  assert.equal(one.title, "Feed");
  assert.ok(one.excerpt.startsWith("PR #15 opened y"));
  assert.equal(Array.from(one.excerpt).length, 80);
});

test("an unknown kind reads as its name, with no data needed", function () {
  var one = entry({ id: 9, kind: "card.archived", card_id: 5, actor: "x", created_at: 1000, data: null }, {});
  assert.deepEqual([one.verb, one.group, one.title], ["card.archived", "other", ""]);
});

test("the relative time and the day separators", function () {
  var now = new Date(2026, 10, 12, 15, 0).getTime();
  assert.equal(relative(now - 20000, now), "just now");
  assert.equal(relative(now - 5 * 60000, now), "5 min ago");
  assert.equal(relative(now - 3 * HOUR, now), "3 h ago");
  var days = byDay([entry(moved({ created_at: now - HOUR }), {}), entry(moved({ created_at: now - 20 * HOUR }), {})], now);
  assert.deepEqual(days.map(function (one) { return one.label; }), ["Today", "Yesterday"]);
});
