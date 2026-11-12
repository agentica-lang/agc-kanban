// `make test` runs this with `node --test`: the label and the target of a card link in the detail panel.
import assert from "node:assert/strict";
import { test } from "node:test";
import { boardCardId, cardLink } from "../../app/javascript/links.js";

test("a GitHub pull request or issue reads as its number", function () {
  assert.equal(cardLink("https://github.com/o/r/pull/7").label, "PR #7");
  assert.equal(cardLink("https://github.com/o/r/issues/3").label, "issue #3");
  assert.equal(cardLink("https://github.com/o/r/pull/7/files").label, "PR #7");
  assert.equal(cardLink("https://github.com/o/r/pull/7#issuecomment-1").label, "PR #7");
  assert.equal(cardLink("https://github.com/o/r/issues/3?x=1").label, "issue #3");
});

test("another URL reads as its host and path", function () {
  assert.equal(cardLink("https://ci.example.com/run/5/?q=1#top").label, "ci.example.com/run/5");
  assert.equal(cardLink("https://example.com").label, "example.com");
  assert.equal(cardLink("https://github.com/o/r/actions/runs/9").label, "github.com/o/r/actions/runs/9");
  assert.equal(cardLink("https://gitlab.com/o/r/pull/7").label, "gitlab.com/o/r/pull/7");
  assert.equal(cardLink("https://example.com/" + "a".repeat(200)).label.length, 60);
});

test("only an http(s) URL is a link; anything else is plain text", function () {
  assert.equal(cardLink("https://github.com/o/r/pull/7").href, "https://github.com/o/r/pull/7");
  ["javascript:alert(1)", "data:text/html,hi", "JAVASCRIPT:alert(1)", "ftp://x.io/f", "not a url", "", null].forEach(function (url) {
    var one = cardLink(url);
    assert.equal(one.href, null);
    assert.equal(one.label, url === null ? "" : url);
  });
});

test("a link to a card of this board gives its id; any other link gives null", function () {
  var origin = "http://kanban.test";
  assert.equal(boardCardId(origin + "/boards/p?card=12", origin, "p"), 12);
  assert.equal(boardCardId(origin + "/boards/p/?label=api&card=3#x", origin, "p"), 3);
  assert.equal(boardCardId(origin + "/boards/my%20board?card=4", origin, "my board"), 4);
  assert.equal(boardCardId(origin + "/boards/other?card=12", origin, "p"), null);
  assert.equal(boardCardId("https://example.com/boards/p?card=12", origin, "p"), null);
  assert.equal(boardCardId(origin + "/boards/p", origin, "p"), null);
  assert.equal(boardCardId(origin + "/boards/p?card=0", origin, "p"), null);
  assert.equal(boardCardId(origin + "/boards/p?card=1x", origin, "p"), null);
  assert.equal(boardCardId("not a url", origin, "p"), null);
});
