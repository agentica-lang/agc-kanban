// `make test` runs this with `node --test`: the Markdown of the card panel stays fast on hostile text, and user text
// is never markup.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Markdown, blocks, capped } from "../../app/javascript/markdown.js";

var BOUND_MS = 500;
var HOSTILE = {
  "open brackets": "[".repeat(100000),
  "labels never closed": "[a".repeat(50000),
  "links never closed": "[a](".repeat(30000),
  "URL prefixes": "http://".repeat(20000),
  "italics never closed": " _a".repeat(50000),
  "bold never closed": "**a".repeat(50000),
  "code never closed": "`a".repeat(50000),
};

for (var [name, text] of Object.entries(HOSTILE)) {
  test("renders " + name + " in under " + BOUND_MS + " ms", function () {
    var start = performance.now();
    blocks(text);
    assert.ok(performance.now() - start < BOUND_MS);
  });
}

function flat(nodes) {
  return nodes.map(function (node) {
    if (typeof node === "string") {
      return node;
    }
    var children = Array.isArray(node.children) ? flat(node.children) : (node.children || "");
    return "<" + node.type + (node.props && node.props.href ? " " + node.props.href : "") + ">" + children;
  }).join("");
}

test("HTML stays text and only http(s) links are links", function () {
  var out = flat(blocks("<script>x</script> [bad](javascript:alert(1)) [ok](https://a.example/1) https://b.example/2."));
  assert.equal(out, "<p><script>x</script> [bad](javascript:alert(1)) <a https://a.example/1>ok <a https://b.example/2>https://b.example/2.");
});

test("a text over the cap is cut whole, with no broken character", function () {
  var text = "a".repeat(49999) + "\u{1F600}" + "b".repeat(1000);
  var head = capped(text);
  assert.equal(head.length, 49999);
  assert.ok(!head.includes("�"));
  assert.equal(capped("short"), "short");
  var out = flat([Markdown.setup({ text: text })()]);
  assert.ok(out.endsWith("<p>\u2026 truncated: 1002 more characters"));
  assert.ok(!out.includes("\uFFFD") && !/[\uD800-\uDBFF](?![\uDC00-\uDFFF])/.test(out));
});
