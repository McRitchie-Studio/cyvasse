// [unit] A player's name fitted to its box (cyvasse/name_fit, task
// cyvasse-splash-name-fit): the largest size that does not overflow, down to
// a floor, and a cut only when the floor still overflows.
import { test } from "node:test";
import assert from "node:assert/strict";

import { fitSize, FIT_STEP_PX } from "cyvasse/name_fit";

// A name `chars` wide in ems, in a box `width` px wide.
const box = (chars, width) => (px) => chars * px > width;

test("a name that fits keeps its size", () => {
  assert.deepEqual(fitSize(19.2, 11, box(10, 200)), { size: 19.2, truncated: false });
});

test("a name too wide shrinks to the largest size that fits, in half pixels", () => {
  const fit = fitSize(19.2, 11, box(12, 160));
  assert.equal(fit.truncated, false);
  assert.ok(12 * fit.size <= 160, `${fit.size}px still overflows`);
  assert.ok(12 * (fit.size + FIT_STEP_PX) > 160, `${fit.size}px is smaller than it needs to be`);
});

test("a name too wide at the floor is cut there, never shrunk past it", () => {
  const sizes = [];
  const fit = fitSize(19.2, 11, (px) => { sizes.push(px); return true; });
  assert.deepEqual(fit, { size: 11, truncated: true });
  assert.equal(Math.min(...sizes), 11);
  assert.ok(sizes.every((px) => px >= 11));
});

test("a floor above the base size never grows the name", () => {
  assert.deepEqual(fitSize(10, 11, box(1, 5)), { size: 10, truncated: true });
  assert.deepEqual(fitSize(10, 11, box(1, 50)), { size: 10, truncated: false });
});
