// The chip of the agent that holds a card: a color from the name, and whether the chip is light (dark text) or dark
// (white text). The server draws the same chip on the home page (src/kanban_web/claimer.agc), so the two files keep the
// same arithmetic, and test/claimer_light.json holds the answer for every hue, checked on both sides.

// A color from the name, so one agent keeps one color.
export function hue(name) {
  var sum = 0;
  for (var i = 0; i < name.length; i++) {
    sum = (sum * 31 + name.charCodeAt(i)) % 360;
  }
  return sum;
}

// The color the chip had before it had tones: hsl(hue 60% 45%). A hue whose color is brighter than LIGHT_ABOVE gets the
// light chip. The brightness squares each channel (sRGB with a gamma of 2, not 2.4) because Agentica has no `pow`;
// the choice only needs to be right to a few percent, since both tones keep 5:1 around the switch, and
// test/web/styles.test.mjs measures the real contrast of every hue.
var SATURATION = 0.6;
var LIGHTNESS = 0.45;
var LIGHT_ABOVE = 0.2;

// One channel of hsl(hue, SATURATION, LIGHTNESS) as the CSS Color spec writes it: `n` is 0, 8 or 4 for red, green, blue.
function channel(n, degrees) {
  var raw = n + degrees / 30;
  var k = raw - 12 * Math.floor(raw / 12);
  var top = Math.min(k - 3, 9 - k);
  return LIGHTNESS - SATURATION * LIGHTNESS * Math.max(-1, Math.min(top, 1));
}

export function lightChip(degrees) {
  var red = channel(0, degrees);
  var green = channel(8, degrees);
  var blue = channel(4, degrees);
  return 0.2126 * red * red + 0.7152 * green * green + 0.0722 * blue * blue > LIGHT_ABOVE;
}
