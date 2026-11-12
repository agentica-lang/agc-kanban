// `make test` runs this with `node --test`: the label and the target of a card link in the detail panel.
import assert from "node:assert/strict";
import { test } from "node:test";
import { cardLink } from "../../app/javascript/links.js";

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
