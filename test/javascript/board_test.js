// [unit] The board geometry and the legacy potential-range walk.
import { test } from "node:test";
import assert from "node:assert/strict";

import { HEXES, HEX_COUNT, hexAt, hexAtXY, neighbors, mirror, distance, cube, rowSize, PLAYER_ZONE, COMPUTER_ZONE } from "cyvasse/board";
import { potentialRange } from "cyvasse/potential_range";

test("the board has 91 hexes in rows of 6 to 11 and back", () => {
  assert.equal(HEXES.length, HEX_COUNT);
  assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(rowSize), [6, 7, 8, 9, 10, 11, 10, 9, 8, 7, 6]);
  assert.deepEqual(hexAt(1), { index: 1, x: 1, y: 1, size: 6 });
  assert.deepEqual(hexAt(41), { index: 41, x: 1, y: 6, size: 11 });
  assert.deepEqual(hexAt(51), { index: 51, x: 11, y: 6, size: 11 });
  assert.deepEqual(hexAt(91), { index: 91, x: 6, y: 11, size: 6 });
  assert.equal(hexAtXY(7, 1), undefined);
});

test("deploy zones are the legacy five rows on each side", () => {
  assert.equal(COMPUTER_ZONE.length, 40);
  assert.equal(PLAYER_ZONE.length, 40);
  assert.ok(COMPUTER_ZONE.every((i) => hexAt(i).y <= 5));
  assert.ok(PLAYER_ZONE.every((i) => hexAt(i).y >= 7));
});

test("mirror turns the board half a turn", () => {
  assert.equal(mirror(1), 91);
  assert.equal(mirror(46), 46);
  for (const hex of HEXES) {
    const flipped = hexAt(mirror(hex.index));
    assert.equal(flipped.y, 12 - hex.y);
    assert.equal(flipped.x, hex.size + 1 - hex.x);
  }
});

test("legacy neighbours are exactly the hexes one step away", () => {
  for (const hex of HEXES) {
    const legacy = neighbors(hex).map((h) => h.index).sort((a, b) => a - b);
    const oracle = HEXES.filter((h) => distance(hex, h) === 1).map((h) => h.index);
    assert.deepEqual(legacy, oracle, `neighbours of hex ${hex.index}`);
  }
  assert.equal(neighbors(hexAt(46)).length, 6);
  assert.equal(neighbors(hexAt(1)).length, 3);
});

test("potential range is the hex disc for every hex and radius", () => {
  for (const radius of [1, 2, 3, 4, 5, 10]) {
    for (const hex of HEXES) {
      const legacy = [...potentialRange(hex, radius)].sort((a, b) => a - b);
      const oracle = HEXES.filter((h) => h !== hex && distance(hex, h) <= radius).map((h) => h.index);
      assert.deepEqual(legacy, oracle, `radius ${radius} around hex ${hex.index}`);
    }
  }
});

test("the dragon's potential range is the six straight lines", () => {
  for (const hex of HEXES) {
    const c = cube(hex);
    const legacy = [...potentialRange(hex, 10, { dragon: true })].sort((a, b) => a - b);
    const oracle = HEXES.filter((h) => {
      if (h === hex) return false;
      const o = cube(h);
      return o.q === c.q || o.r === c.r || o.s === c.s;
    }).map((h) => h.index);
    assert.deepEqual(legacy, oracle, `dragon lines from hex ${hex.index}`);
  }
});

test("a radius of zero reaches nothing (the trebuchet cannot move)", () => {
  assert.equal(potentialRange(hexAt(46), 0).size, 0);
});
