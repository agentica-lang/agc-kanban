// `make test` runs this with `node --test`: cascade checks of the built stylesheet that a browser would show only on
// screen. Rules of the same weight are decided by their order, which moves when a partial changes, and a heavier rule
// or one in a media query wins over both; so the check runs the cascade itself over every rule that can reach the
// element, in or out of `@media` (each media query is taken as matching).
import assert from "node:assert/strict";
import { test } from "node:test";
import { compile, compileString } from "sass";
import { lightChip } from "../../app/javascript/claimer.js";
import { WIDE } from "../../app/javascript/wide.js";

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

// The agent chip of a card: `<button class="claimer pick">` in the meta line of the card, on the board page. A hue that
// takes the light chip has the class `light` too (claimer.js).
function boardChip(light) {
  return {
    tag: "button",
    classes: ["claimer", "pick"].concat(light ? ["light"] : []),
    ancestors: ["meta", "card", "card-done", "priority-0", "priority-1", "priority-2", "priority-3", "changed", "open", "cards", "column",
      "column-done", "board", "board-body", "board-page"],
  };
}

// The chip of an agent on the home page: `<span class="claimer">` in the facts of a board's card.
function homeChip(light) {
  return { tag: "span", classes: ["claimer"].concat(light ? ["light"] : []), ancestors: ["facts", "board-card", "boards", "home"] };
}

var CLAIMER = boardChip(false);

// The color a browser paints for `hsl(hue S% L%)`, as 8-bit channels (the CSS Color rule), and the WCAG relative luminance.
function paint(hue, saturation, lightness) {
  var s = saturation / 100;
  var l = lightness / 100;
  var a = s * Math.min(l, 1 - l);
  return [0, 8, 4].map(function (n) {
    var k = (n + hue / 30) % 12;
    return Math.round((l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))) * 255);
  });
}

function luminance(rgb) {
  var [r, g, b] = rgb.map(function (c) {
    var v = c / 255;
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(one, other) {
  var [hi, lo] = [luminance(one), luminance(other)].sort(function (x, y) { return y - x; });
  return (hi + 0.05) / (lo + 0.05);
}

function hexRgb(hex) {
  var digits = hex.length === 4 ? hex.slice(1).replace(/./g, "$&$&") : hex.slice(1);
  return [0, 2, 4].map(function (i) { return parseInt(digits.slice(i, i + 2), 16); });
}

// The contrast of the chip of `hue`, from the background and the text that the stylesheet gives `element`. A value
// that is not a literal color (a theme token such as `var(--card)`) would make the chip change with the theme, which
// this check does not follow, so it is an error: the chip must look the same in both.
function chipContrast(css, element, hue) {
  var background = winner(rules(css), element, "background").value;
  var color = winner(rules(css), element, "color").value;
  var parts = /^hsl\(var\(--hue\),? (\d+)%,? (\d+)%\)$/.exec(background);
  assert.ok(parts && /^#[0-9a-f]{3}([0-9a-f]{3})?$/.test(color), "a literal chip color: " + background + " on " + color);
  return contrast(paint(hue, Number(parts[1]), Number(parts[2])), hexRgb(color));
}

// The lowest contrast over the 360 hues, with the chip of each as claimer.js picks it.
function worst(css, chip) {
  var found = { ratio: Infinity, hue: -1 };
  for (var hue = 0; hue < 360; hue++) {
    var ratio = chipContrast(css, chip(lightChip(hue)), hue);
    if (ratio < found.ratio) {
      found = { ratio: ratio, hue: hue };
    }
  }
  return found;
}

test("the agent chip reaches 4.5:1 for every hue, on the board and on the home page, in both themes", function () {
  // The chip has literal colors (chipContrast refuses a token), so the light and the dark theme paint the same pair.
  [boardChip, homeChip].forEach(function (chip) {
    var found = worst(built, chip);
    assert.ok(found.ratio >= 4.5, "hue " + found.hue + " has " + found.ratio.toFixed(2) + ":1");
  });
});

test("the check fails the old chip: white text on hsl(hue 60% 45%) for every hue", function () {
  var old = built + compileString(".card .meta .claimer.pick, .card .meta .claimer.pick.light { background: hsl(var(--hue) 60% 45%); color: #fff; }").css;
  var found = worst(old, boardChip);
  assert.ok(found.ratio < 2.5, "the worst old hue has " + found.ratio.toFixed(2) + ":1");
});

test("the light chip has dark text and the dark chip white, so the cascade never leaves the white on a light chip", function () {
  assert.equal(winner(rules(built), boardChip(false), "color").value, "#fff");
  assert.notEqual(winner(rules(built), boardChip(true), "color").value, "#fff");
  assert.equal(winner(rules(built), homeChip(false), "color").value, "#fff");
  assert.notEqual(winner(rules(built), homeChip(true), "color").value, "#fff");
});

test("the blocked chip reaches 4.5:1 on the card and the page behind it, in the light theme", function () {
  var light = /--card: (#[0-9a-f]+);[^}]*?--warn: (#[0-9a-f]+);/.exec(built.slice(built.indexOf(":root")));
  assert.ok(light, "the light tokens");
  var warn = hexRgb(light[2]);
  [light[1], "#f4f5f7", "#e9ebef"].forEach(function (back) {
    assert.ok(contrast(warn, hexRgb(back)) >= 4.5, back + " behind " + light[2]);
  });
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

// The theme tokens of the built stylesheet: the light ones in `:root`, the dark ones in `:root[data-theme=dark]`.
function tokens(css, head) {
  var start = css.startsWith(head + " {") ? 0 : css.indexOf("\n" + head + " {");
  assert.ok(start >= 0, head);
  var map = {};
  css.slice(start, css.indexOf("}", start)).replace(/--([\w-]+): (#[0-9a-f]+);/g, function (all, name, value) { map[name] = value; });
  return map;
}

// The facts panel of the card window (`<div class="detail-side">`) and what is in it, as the drawer of a wide screen has
// them: the rules of `@media (min-width: ...)` count as matching, as in the cascade check above.
var INSIDE = ["drawer", "drawer-modal", "drawer-body", "detail", "detail-side"];
var SIDE = { tag: "div", classes: ["detail-side"], ancestors: INSIDE.slice(0, 4) };
var NAME = { tag: "dt", classes: [], ancestors: INSIDE };
var LINK = { tag: "a", classes: ["ref"], ancestors: INSIDE };
var CHIP = { tag: "span", classes: ["label"], ancestors: INSIDE };

function token(value) {
  var found = /^var\(--([\w-]+)\)$/.exec(value);
  assert.ok(found, "a theme token: " + value);
  return found[1];
}

// The lowest contrast, in both themes, of the muted names and the links on the panel and of the text on a chip.
function sideContrast(css) {
  var list = rules(css);
  var panel = token(winner(list, SIDE, "background").value);
  var chip = token(winner(list, CHIP, "background").value);
  var name = token(winner(list, NAME, "color").value);
  var link = token(winner(list, LINK, "color").value);
  return [tokens(css, ":root"), tokens(css, ":root[data-theme=dark]")].map(function (theme) {
    return Math.min(contrast(hexRgb(theme[name]), hexRgb(theme[panel])), contrast(hexRgb(theme[link]), hexRgb(theme[panel])),
      contrast(hexRgb(theme.text), hexRgb(theme[chip])));
  });
}

test("the facts panel of the card window keeps 4.5:1 for the muted names, the links and the chips, in both themes", function () {
  sideContrast(built).forEach(function (ratio, theme) {
    assert.ok(ratio >= 4.5, ["light", "dark"][theme] + " has " + ratio.toFixed(2) + ":1");
  });
});

test("the check fails the old panel: the muted names and the links on the panel color", function () {
  var old = built + compileString(".drawer-modal .detail .detail-side { background: var(--panel); }").css;
  assert.ok(sideContrast(old)[0] < 4.5);
});

test("the stylesheet and wide.js have the same width for the card window, and no range leaves a gap at 700 px", function () {
  assert.ok(built.includes(WIDE), WIDE);
  assert.equal(built.includes("701px"), false);
});

test("a collapsed column stays a strip on a phone: its rule wins over the phone width of a column", function () {
  var strip = { tag: "section", classes: ["column", "column-collapsed"], ancestors: ["board", "board-body", "board-page"] };
  assert.equal(winner(rules(built), strip, "flex").value, "0 0 2.75rem");
  assert.equal(winner(rules(built), strip, "max-width").value, "2.75rem");
  var column = { tag: "section", classes: ["column"], ancestors: strip.ancestors };
  assert.equal(winner(rules(built), column, "flex").value, "0 0 85vw", "the phone rule of a column is the last one");
});

// The room above the first field of the side drawer: the top padding of its body, which scrolls and so clips the
// rest, less the outline and the offset of the search input's focus ring. Below zero, the ring is cut off.
function roomAboveSearch(css) {
  var body = { tag: "div", classes: ["drawer-body"], ancestors: ["drawer"] };
  var top = winner(rules(css), body, "padding").value.split(/\s+/)[0];
  var px = top === "0" ? 0 : /^([\d.]+)rem$/.test(top) ? parseFloat(top) * 16 : parseFloat(top);
  var ring = /\.search-input:focus-visible \{\s*outline: (\d+)px [^;]*;\s*outline-offset: (\d+)px;/.exec(css);
  assert.ok(ring, "the focus ring of the search input");
  return px - Number(ring[1]) - Number(ring[2]);
}

test("the drawer body leaves room above the search input for its focus ring", function () {
  assert.ok(roomAboveSearch(built) >= 0, roomAboveSearch(built) + "px");
  assert.ok(roomAboveSearch(built + compileString(".drawer-body { padding: 0 1rem 1rem; }").css) < 0, "the old padding");
});
