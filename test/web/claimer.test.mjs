// `make test` runs this with `node --test`: the chip of an agent on the board (claimer.js) and on the home page
// (src/kanban_web/claimer.agc) must pick the same tone for every hue. Both are checked against test/claimer_light.json;
// test/claimer_test.agc is the other half. The contrast of each tone is measured in styles.test.mjs.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { hue, lightChip } from "../../app/javascript/claimer.js";

var light = JSON.parse(readFileSync(new URL("../claimer_light.json", import.meta.url), "utf8"));

test("every hue has the tone of the shared file, and both tones are used", function () {
  assert.equal(light.length, 360);
  light.forEach(function (expected, degrees) {
    assert.equal(lightChip(degrees), expected, "hue " + degrees);
  });
  assert.ok(light.includes(true) && light.includes(false));
});

test("the hue of a name is the one the home page draws", function () {
  assert.deepEqual(["bob", "seed", "claude-code"].map(hue), [157, 57, 28]);
});
