// [unit] The game-over modal's points line: the server's points, worded for a
// win, for a loss or draw, with a signed-in player's rank, and nothing when
// the game put nothing on the board.
import { test } from "node:test";
import assert from "node:assert/strict";

import { pointsLine } from "cyvasse/game_over";

test("a win names its points on the leaderboard", () => {
  assert.equal(pointsLine({ points: 3, win: true }), "+3 points on the leaderboard.");
});

test("a loss or a draw names the point for finishing", () => {
  assert.equal(pointsLine({ points: 1, win: false }), "+1 point on the leaderboard for finishing.");
});

test("a signed-in player's new rank follows the points", () => {
  assert.equal(pointsLine({ points: 3, win: true, rank: 4 }), "+3 points on the leaderboard. You’re now #4.");
  assert.equal(pointsLine({ points: 1, win: false, rank: 12 }), "+1 point on the leaderboard for finishing. You’re now #12.");
});

test("a seat the computer held, or a game that does not count, has no line", () => {
  assert.equal(pointsLine({ points: 0, win: false }), "");
  assert.equal(pointsLine({ points: null, win: false, rank: 3 }), "");
  assert.equal(pointsLine({}), "");
  assert.equal(pointsLine(), "");
});
