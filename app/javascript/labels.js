// The color of a label chip: the board gives each label a #rrggbb color, and the text takes the darker or the lighter of
// two inks, whichever has the higher WCAG contrast with it.
var DARK = "#1f2328";
var LIGHT = "#ffffff";
var HEX = /^#[0-9a-f]{6}$/i;

function luminance(hex) {
  var channels = [1, 3, 5].map(function (start) {
    var value = parseInt(hex.slice(start, start + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

export function validColor(color) {
  return typeof color === "string" && HEX.test(color);
}

// The ink for text on `color`.
export function textColor(color) {
  var l = luminance(color);
  var dark = (l + 0.05) / (luminance(DARK) + 0.05);
  var light = (luminance(LIGHT) + 0.05) / (l + 0.05);
  return dark >= light ? DARK : LIGHT;
}

// The inline style of a chip, or "" for a label with no valid color (the stylesheet's chip stays).
export function chipStyle(color) {
  return validColor(color) ? "background:" + color + ";color:" + textColor(color) : "";
}

// The color of each label name of a board snapshot's `labels`.
export function colorsOf(labels) {
  var map = {};
  (Array.isArray(labels) ? labels : []).forEach(function (label) { map[label.name] = label.color; });
  return map;
}
