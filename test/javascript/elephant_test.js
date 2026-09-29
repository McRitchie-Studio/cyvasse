// [unit] Rule change of September 29, 2026 (Alex): the elephant moves two
// hexes, not three. It is strong but slow, so it belongs on the front line.
// test/models/cyvasse_rules/elephant_rules_test.rb holds the server to the
// same cases.
//
// Hex numbers are the legacy data-hexIndex: 46 is the middle of the board and
// 47 48 49 run to its right along the middle row.
import { test } from "node:test";
import assert from "node:assert/strict";

import { HEXES, hexAt, distance } from "cyvasse/board";
import { UNIT_TYPES } from "cyvasse/units";
import { legalActions } from "cyvasse/rules";
import { position } from "./support/fixtures.js";

const ALLY = 1;
const ENEMY = 0;
const disc = (origin, r) => HEXES.filter((h) => h.index !== origin && distance(hexAt(origin), h) <= r).map((h) => h.index);

test("the elephant's move range is two", () => {
  assert.equal(UNIT_TYPES.elephant.moveRange, 2);
});

test("a lone elephant reaches every hex within two and none at three", () => {
  const { moves } = legalActions(position({ 46: [ALLY, "elephant"] }), 46);
  assert.deepEqual(moves, disc(46, 2));
  assert.ok(moves.includes(48), "two hexes along the row");
  assert.ok(!moves.includes(49), "three hexes along the row is out of reach");
  assert.ok(disc(46, 3).some((hex) => !moves.includes(hex)), "control: some hex at three exists and is refused");
});

test("an elephant captures an enemy two hexes away, and not three", () => {
  assert.deepEqual(legalActions(position({ 46: [ALLY, "elephant"], 48: [ENEMY, "spearman"] }), 46).attacks, [48]);
  assert.deepEqual(legalActions(position({ 46: [ALLY, "elephant"], 49: [ENEMY, "spearman"] }), 46).attacks, []);
});
