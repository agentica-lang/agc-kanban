// `make test` runs this with `node --test`: the colors of the label chips. The ink is the one with the higher contrast
// (WCAG 2) for every color of the palette that the server draws from, and a value that is no #rrggbb styles nothing.
import assert from "node:assert/strict";
import { test } from "node:test";
import { chipStyle, colorsOf, textColor, validColor } from "../../app/javascript/labels.js";

var PALETTE = ["#d73a4a", "#0075ca", "#7057ff", "#008672", "#e99695", "#fbca04", "#0e8a16", "#d876e3", "#1d76db", "#b60205", "#c5def5", "#bfd4f2"];

function luminance(hex) {
  var c = [1, 3, 5].map(function (i) {
    var v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function contrast(a, b) {
  var hi = Math.max(luminance(a), luminance(b));
  var lo = Math.min(luminance(a), luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

test("the text on every palette color is readable and light colors get the dark ink", function () {
  PALETTE.forEach(function (color) {
    assert.ok(contrast(color, textColor(color)) >= 4.5, color + " has too little contrast");
  });
  assert.equal(textColor("#ffffff"), "#1f2328");
  assert.equal(textColor("#000000"), "#ffffff");
  assert.equal(textColor("#fbca04"), "#1f2328");
  assert.equal(textColor("#b60205"), "#ffffff");
});

test("a chip is styled only with a #rrggbb color", function () {
  assert.equal(chipStyle("#0075ca"), "background:#0075ca;color:#ffffff");
  ["", "red", "#123", "#12345g", "#0075ca; x:y", undefined, null, 5].forEach(function (value) {
    assert.equal(validColor(value), false);
    assert.equal(chipStyle(value), "");
  });
});

test("the colors of a snapshot are read by name, with no labels as none", function () {
  assert.deepEqual(colorsOf([{ id: 1, name: "api", color: "#0075ca" }, { id: 2, name: "ui", color: "#7057ff" }]), { api: "#0075ca", ui: "#7057ff" });
  assert.deepEqual(colorsOf(undefined), {});
});
