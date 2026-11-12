// `make test` runs this with `node --test`: cascade checks of the built stylesheet that a browser would show only on
// screen. Rules of the same weight are decided by their order, which moves when a partial changes, and a heavier rule
// or one in a media query wins over both; so the check runs the cascade itself over every rule that can reach the
// element, in or out of `@media` (each media query is taken as matching).
import assert from "node:assert/strict";
import { test } from "node:test";
import { compile, compileString } from "sass";

var ROOT = new URL("../../app/stylesheets/", import.meta.url).pathname;
var built = compile(ROOT + "application.scss", { style: "expanded" }).css;

// The style rules in the order of the stylesheet, with the ones inside `@media` and `@supports`; other at-rules
// (keyframes, font faces) are left out. Each is { selectors: [...], body }.
function rules(text) {
  var found = [];
  var i = 0;
  function block(stop) {
    var start = i;
    while (i < text.length) {
      var ch = text[i];
      if (ch === "}") {
        i += 1;
        return;
      }
      if (ch === ";") {
        start = i + 1;
      } else if (ch === "{") {
        var head = text.slice(start, i).trim();
        i += 1;
        if (head.startsWith("@media") || head.startsWith("@supports")) {
          block();
        } else if (head.startsWith("@")) {
          skip();
        } else {
          var end = text.indexOf("}", i);
          found.push({ selectors: list(head), body: text.slice(i, end) });
          i = end + 1;
        }
        start = i;
        continue;
      }
      i += 1;
    }
  }
  function skip() {
    var depth = 1;
    while (i < text.length && depth > 0) {
      depth += text[i] === "{" ? 1 : text[i] === "}" ? -1 : 0;
      i += 1;
    }
  }
  block();
  return found;
}

// The selectors of a list: split on the commas outside parentheses, so `:is(.a, .b) .c` stays one.
function list(head) {
  var parts = [];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < head.length; i++) {
    depth += head[i] === "(" ? 1 : head[i] === ")" ? -1 : 0;
    if (head[i] === "," && depth === 0) {
      parts.push(head.slice(start, i).trim());
      start = i + 1;
    }
  }
  parts.push(head.slice(start).trim());
  return parts;
}

// `selector` with what is inside parentheses left out, so a space or a combinator there splits no compound.
function bare(selector) {
  var out = "";
  var depth = 0;
  for (var i = 0; i < selector.length; i++) {
    if (selector[i] === ")") {
      depth -= 1;
    }
    if (depth === 0) {
      out += selector[i];
    }
    if (selector[i] === "(") {
      depth += 1;
    }
  }
  return out;
}

function compounds(selector) {
  return selector.replace(/\s*([>+~])\s*/g, " ").split(/\s+/).filter(Boolean);
}

function classes(compound) {
  return (compound.match(/\.[\w-]+/g) || []).map(function (one) { return one.slice(1); });
}

// [ids, classes + attributes + pseudo-classes, tags] of a selector. `reaches` has thrown on :not/:is/:where/:has
// before a selector gets here, so their arguments never need counting.
function specificity(selector) {
  var ids = (selector.match(/#[\w-]+/g) || []).length;
  var weight = (selector.match(/\.[\w-]+|\[[^\]]*\]|:(?!:)[\w-]+/g) || []).length;
  var tags = compounds(selector).filter(function (one) { return /^[a-z]/i.test(one); }).length;
  return ids * 10000 + weight * 100 + tags;
}

// Whether `selector` can select `element`: its last compound names only what the element has (its tag, classes and
// any `aria-pressed`, with no state such as :hover), and every class before it is on one of the element's ancestors.
function reaches(selector, element) {
  var parts = compounds(bare(selector));
  var last = parts[parts.length - 1];
  var tag = (/^[a-z][\w-]*|^\*/i.exec(last) || [""])[0];
  // A rule for another element (`main:not(.board)`) is out whatever its pseudo-classes say. The tag comes from the
  // selector without its parentheses, so `.pick:not(.x span)` ends in `.pick:not()`, not in `span`.
  if (tag !== "" && tag !== "*" && tag !== element.tag) {
    return false;
  }
  // These take selectors as arguments, which this check does not read: a rule with one that might reach the element
  // must not pass unseen.
  if (/:(not|is|where|has)\(/.test(selector)) {
    throw new Error("the cascade check does not read " + selector);
  }
  var rest = last.slice(tag.length).replace(/\.[\w-]+/g, "").replace(/\[aria-pressed(="(true|false)")?\]/g, "");
  if (rest !== "") {
    return false;
  }
  if (!classes(last).every(function (one) { return element.classes.indexOf(one) !== -1; })) {
    return false;
  }
  return parts.slice(0, -1).every(function (part) {
    return classes(part).every(function (one) { return element.ancestors.indexOf(one) !== -1; });
  });
}

// The `property` the cascade gives `element` among `list`: the heaviest rule, the last one among equals.
function winner(list, element, property) {
  var best = null;
  var pattern = new RegExp("(?:^|;)\\s*" + property + ":\\s*([^;]+)");
  list.forEach(function (rule, order) {
    var value = pattern.exec(rule.body);
    if (!value) {
      return;
    }
    rule.selectors.forEach(function (selector) {
      if (!reaches(selector, element)) {
        return;
      }
      var weight = specificity(selector);
      if (!best || weight > best.weight || (weight === best.weight && order >= best.order)) {
        best = { weight: weight, order: order, value: value[1].trim(), selector: selector };
      }
    });
  });
  return best;
}

// The agent chip of a card: `<button class="claimer pick">` in the meta line of the card, on the board page.
var CLAIMER = {
  tag: "button",
  classes: ["claimer", "pick"],
  ancestors: ["meta", "card", "card-done", "priority-0", "priority-1", "priority-2", "priority-3", "changed", "open", "cards", "column",
    "column-done", "board", "board-body", "board-page"],
};

test("the agent chip on a card keeps its white text", function () {
  assert.equal(winner(rules(built), CLAIMER, "color").value, "#fff");
});

test("the check catches a rule that takes the white off later, from a media query, or with more weight", function () {
  // As heavy as the white: it wins by coming later, in or out of a media query.
  ["@media (max-width: 700px) { .card .pick { color: inherit; } }", ".card .pick { color: inherit; }"].forEach(function (extra) {
    assert.equal(winner(rules(built + compileString(extra).css), CLAIMER, "color").value, "inherit", extra);
  });
  // Heavier: it wins from before the white, so only its weight can make it win.
  [".card .meta .pick { color: inherit; }", "@media (max-width: 700px) { .card .meta .claimer { color: inherit; } }",
    ".card button.claimer { color: inherit; }"].forEach(function (extra) {
    assert.equal(winner(rules(compileString(extra).css + built), CLAIMER, "color").value, "inherit", extra);
  });
  // Lighter, even later: the white stays.
  assert.equal(winner(rules(built + compileString(".pick { color: inherit; }").css), CLAIMER, "color").value, "#fff");
});

test("a selector the check cannot read stops it instead of passing unseen", function () {
  [".card .pick:not(.on) { color: inherit; }", ".card .pick:not(.x span) { color: inherit; }",
    ":is(.card, .other) .pick { color: inherit; }"].forEach(function (extra) {
    var css = built + compileString(extra).css;
    assert.throws(function () { winner(rules(css), CLAIMER, "color"); }, /does not read/, extra);
  });
});
