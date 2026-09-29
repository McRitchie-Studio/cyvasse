// [unit] The computer's pacing on /play: select, move and second-jump delays
// fall in their ranges, and pace 0 makes them all zero.
import { test } from "node:test";
import assert from "node:assert/strict";

import { BOT_PACING, botDelays } from "cyvasse/pacing";

test("the ranges are the ones Alex asked for", () => {
  assert.deepEqual(BOT_PACING, { select: [2000, 5000], move: [3000, 5000], second: [2000, 3000] });
});

test("every delay falls in its range, at both ends of the random draw", () => {
  for (const r of [0, 0.25, 0.5, 0.999]) {
    const delays = botDelays(() => r);
    for (const key of ["select", "move", "second"]) {
      const [low, high] = BOT_PACING[key];
      assert.ok(delays[key] >= low && delays[key] <= high, `${key} ${delays[key]} in ${low}-${high}`);
    }
  }
  assert.deepEqual(botDelays(() => 0), { select: 2000, move: 3000, second: 2000 });
  assert.deepEqual(botDelays(() => 1), { select: 5000, move: 5000, second: 3000 });
});

test("pace 0 makes the turn instant", () => {
  assert.deepEqual(botDelays(() => 0.7, 0), { select: 0, move: 0, second: 0 });
});
