// [unit] The turn a player reads counts full moves: both sides' moves are one
// turn, so a player's ninth move is "Turn 9", never "Turn 17".
import { test } from "node:test";
import assert from "node:assert/strict";

import { fullMove } from "cyvasse/turns";

test("before play there is no turn", () => {
  assert.equal(fullMove(0), 0);
  assert.equal(fullMove(undefined), 0);
  assert.equal(fullMove(null), 0);
});

test("each side's first move is turn 1, their second turn 2", () => {
  assert.deepEqual([1, 2, 3, 4, 5, 6].map(fullMove), [1, 1, 2, 2, 3, 3]);
});

test("the ninth move of either side is turn 9 (the audit's 'Turn 17')", () => {
  assert.equal(fullMove(17), 9, "the first mover's ninth move");
  assert.equal(fullMove(18), 9, "the second mover's ninth move");
});

test("a server turn sent as a string counts the same", () => {
  assert.equal(fullMove("17"), 9);
});
