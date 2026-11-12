// `make test` runs this with `node --test`: the panel writes the time in each column as `kanban card show` does. The
// same cases are checked against Times.lines by test/times_test.agc.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { lines } from "../../app/javascript/times.js";

var cases = JSON.parse(readFileSync(new URL("../times_lines.json", import.meta.url), "utf8"));

test("the lines match the shared cases", function () {
  cases.forEach(function (one) {
    assert.deepEqual(lines(one.times, 0), one.lines);
  });
});

test("an open card counts its current column on", function () {
  var open = cases[2].times;
  assert.deepEqual(lines(open, 5 * 60000), ["Todo 15 min · Doing 1 h 50 min", "50 min in Doing"]);
});
