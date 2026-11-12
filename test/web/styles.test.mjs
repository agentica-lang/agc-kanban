// `make test` runs this with `node --test`: cascade checks of the built stylesheet that a browser would show only on
// screen. Two rules of the same specificity are decided by their order, which moves when a partial changes.
import assert from "node:assert/strict";
import { test } from "node:test";
import { compile } from "sass";

var css = compile(new URL("../../app/stylesheets/application.scss", import.meta.url).pathname, { style: "expanded" }).css;

// Each rule as { selectors, body }, in the order of the stylesheet; @media blocks are left out (only the top level).
function rules(text) {
  var found = [];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] === "{") {
      if (depth === 0) {
        var head = text.slice(start, i).trim();
        var end = text.indexOf("}", i);
        if (!head.startsWith("@") && text.slice(i + 1, end).indexOf("{") === -1) {
          found.push({ selectors: head.split(",").map(function (one) { return one.trim(); }), body: text.slice(i + 1, end) });
        }
      }
      depth += 1;
    } else if (text[i] === "}") {
      depth -= 1;
      start = i + 1;
    }
  }
  return found;
}

test("the agent chip on a card keeps its white text: no later rule of the same weight gives it another color", function () {
  // The claimer chip is `<button class="claimer pick">` in `.card`; these selectors all weigh two classes.
  var same = [".card .claimer", ".card .pick", ".card button"];
  var colors = rules(css)
    .filter(function (rule) { return rule.selectors.some(function (one) { return same.indexOf(one) !== -1; }); })
    .map(function (rule) { return /(?:^|;)\s*color:\s*([^;]+)/.exec(rule.body); })
    .filter(Boolean)
    .map(function (match) { return match[1].trim(); });
  assert.equal(colors[colors.length - 1], "#fff");
});
