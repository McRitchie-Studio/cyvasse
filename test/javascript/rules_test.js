// [unit] Moves, ranges and captures, held to the legacy rules.
//
// Hex numbers are the legacy data-hexIndex. The middle of the board is 46
// (row 6, x 6); its neighbours are 35 36 45 47 56 57, and 48 is two hexes
// to its right along the middle row.
import { test } from "node:test";
import assert from "node:assert/strict";

import { HEXES, hexAt, neighbors, distance, cube } from "cyvasse/board";
import { UNIT_TYPES } from "cyvasse/units";
import { legalActions, inARow } from "cyvasse/rules";
import { position, seeded } from "./support/fixtures.js";

const ALLY = 1;
const ENEMY = 0;
const ring = (origin, r) => HEXES.filter((h) => distance(hexAt(origin), h) === r).map((h) => h.index);
const disc = (origin, r) => HEXES.filter((h) => h.index !== origin && distance(hexAt(origin), h) <= r).map((h) => h.index);

test("a lone rabble moves anywhere within three and captures nothing", () => {
  const { moves, attacks } = legalActions(position({ 46: [ALLY, "rabble"] }), 46);
  assert.deepEqual(moves, disc(46, 3));
  assert.deepEqual(attacks, []);
});

test("friends and mountains block the way; enemies block it too", () => {
  const walled = { 46: [ALLY, "rabble"] };
  for (const n of [35, 36, 45, 56, 57]) walled[n] = [ALLY, "mountain"];
  walled[47] = [ENEMY, "spearman"];
  const { moves, attacks } = legalActions(position(walled), 46);
  assert.deepEqual(moves, []);
  assert.deepEqual(attacks, [], "a rabble (1) cannot take a spearman (2)");
});

test("a unit captures an enemy of equal or lower strength, not a stronger one", () => {
  const board = position({ 46: [ALLY, "spearman"], 47: [ENEMY, "rabble"], 45: [ENEMY, "king"], 36: [ENEMY, "heavyhorse"] });
  const { attacks } = legalActions(board, 46);
  assert.deepEqual(attacks, [45, 47], "takes the rabble (1) and the king (2), not the heavy horse (3)");
});

test("a capture ends the path: nothing beyond the captured enemy is reached through it", () => {
  const board = { 46: [ALLY, "elephant"], 47: [ENEMY, "rabble"] };
  for (const n of [35, 36, 45, 56, 57]) board[n] = [ALLY, "mountain"];
  const { moves, attacks } = legalActions(position(board), 46);
  assert.deepEqual(attacks, [47]);
  assert.deepEqual(moves, []);
});

test("the defender's trump blocks: a light horse cannot take a spearman", () => {
  const board = position({ 46: [ALLY, "lighthorse"], 47: [ENEMY, "spearman"] });
  assert.deepEqual(legalActions(board, 46).attacks, []);

  const heavy = position({ 46: [ALLY, "heavyhorse"], 47: [ENEMY, "spearman"] });
  assert.deepEqual(legalActions(heavy, 46).attacks, [47], "the spearman trumps only the light horse");
});

test("the defender's trump blocks: an elephant cannot take a crossbowman", () => {
  const board = position({ 46: [ALLY, "elephant"], 47: [ENEMY, "crossbowman"] });
  assert.deepEqual(legalActions(board, 46).attacks, []);
});

test("a crossbowman shoots two hexes over friends and foes, and trumps the elephant", () => {
  const board = position({
    46: [ALLY, "crossbowman"],
    47: [ALLY, "rabble"],
    48: [ENEMY, "elephant"],
    45: [ENEMY, "rabble"],
    44: [ENEMY, "heavyhorse"]
  });
  const { moves, attacks } = legalActions(board, 46);
  assert.deepEqual(attacks, [45, 48], "the elephant (4) falls to its trump; the heavy horse (3) is too strong");
  assert.deepEqual(moves, [35, 36, 56, 57], "it walks one hex, and only onto empty ones");
});

test("a shooter stays put and never captures by moving", () => {
  const board = position({ 46: [ALLY, "catapult"], 47: [ENEMY, "rabble"] });
  const { moves, attacks } = legalActions(board, 46);
  assert.ok(attacks.includes(47));
  assert.ok(!moves.includes(47));
});

test("the trebuchet cannot move but reaches three hexes, and trumps the dragon", () => {
  const board = position({ 46: [ALLY, "trebuchet"], 49: [ENEMY, "dragon"], 43: [ENEMY, "rabble"], 44: [ENEMY, "spearman"] });
  const { moves, attacks } = legalActions(board, 46);
  assert.deepEqual(moves, []);
  assert.deepEqual(attacks, [43, 49], "the rabble (1) and the dragon (trumped); not the spearman (2 > 1)");
});

test("a mountain in the line of fire shelters the hex directly behind it", () => {
  const open = position({ 46: [ALLY, "crossbowman"], 48: [ENEMY, "rabble"] });
  assert.deepEqual(legalActions(open, 46).attacks, [48]);

  const sheltered = position({ 46: [ALLY, "crossbowman"], 47: [ENEMY, "mountain"], 48: [ENEMY, "rabble"] });
  const { attacks, rangeRings } = legalActions(sheltered, 46);
  assert.deepEqual(attacks, []);
  assert.equal(rangeRings.get(47), 40, "a mountain in line with the shooter");
  assert.equal(rangeRings.get(48), 31, "in its shadow");
});

test("a mountain off the line of fire shades everything behind it", () => {
  const origin = 46;
  const mountain = 37; // two away, on no axis through 46
  assert.equal(distance(hexAt(origin), hexAt(mountain)), 2);
  assert.ok(!inARow(hexAt(origin), hexAt(mountain)));
  const behind = neighbors(hexAt(mountain)).map((h) => h.index).filter((i) => distance(hexAt(origin), hexAt(i)) === 3);
  assert.ok(behind.length > 0);

  for (const target of behind) {
    const open = position({ [origin]: [ALLY, "catapult"], [target]: [ENEMY, "rabble"] });
    assert.deepEqual(legalActions(open, origin).attacks, [target], `control: ${target} is in reach`);

    const shaded = position({ [origin]: [ALLY, "catapult"], [mountain]: [ENEMY, "mountain"], [target]: [ENEMY, "rabble"] });
    assert.deepEqual(legalActions(shaded, origin).attacks, [], `${target} sits in the mountain's shadow`);
  }
});

test("the dragon moves along six straight lines, flying over friends and mountains", () => {
  const board = position({ 46: [ALLY, "dragon"], 47: [ALLY, "rabble"], 45: [ENEMY, "mountain"] });
  const { moves } = legalActions(board, 46);
  const lines = HEXES.filter((h) => {
    if (h.index === 46) return false;
    const c = cube(h);
    return c.q === 0 || c.r === 0 || c.s === 0;
  }).map((h) => h.index);
  assert.deepEqual(moves, lines.filter((i) => i !== 47 && i !== 45));
  assert.ok(moves.includes(48) && moves.includes(44), "it lands beyond what it flew over");
});

test("the dragon captures any foot soldier on its lines and flies on past it", () => {
  const board = position({ 46: [ALLY, "dragon"], 48: [ENEMY, "elephant"], 50: [ENEMY, "king"] });
  const { moves, attacks } = legalActions(board, 46);
  assert.deepEqual(attacks, [48, 50]);
  assert.ok(moves.includes(49) && moves.includes(51));
});

test("a crossbowman or dragon stops the dragon; a trebuchet or catapult repels it", () => {
  const stops = position({ 46: [ALLY, "dragon"], 48: [ENEMY, "crossbowman"], 44: [ENEMY, "dragon"] });
  const stopped = legalActions(stops, 46);
  assert.ok(stopped.attacks.includes(48) && stopped.attacks.includes(44));
  assert.ok(!stopped.moves.includes(49) && !stopped.moves.includes(43));

  const repels = position({ 46: [ALLY, "dragon"], 48: [ENEMY, "catapult"], 44: [ENEMY, "trebuchet"] });
  const repelled = legalActions(repels, 46);
  assert.ok(!repelled.attacks.includes(48) && !repelled.attacks.includes(44));
  assert.ok(!repelled.moves.includes(49) && !repelled.moves.includes(43));
  assert.ok(repelled.moves.includes(47) && repelled.moves.includes(45));
});

test("cavalry: a full first jump, then a second jump of two", () => {
  const board = position({ 46: [ALLY, "lighthorse"] });
  assert.deepEqual(legalActions(board, 46).moves, disc(46, 3));
  assert.deepEqual(legalActions(board, 46, { jump: 2 }).moves, disc(46, 2));

  const heavy = position({ 46: [ALLY, "heavyhorse"] });
  assert.deepEqual(legalActions(heavy, 46).moves, disc(46, 2));
  assert.deepEqual(legalActions(heavy, 46, { jump: 2 }).moves, disc(46, 2));
});

test("the first cavalry jump previews the second as 6x rings, never as moves", () => {
  const { moves, rings } = legalActions(position({ 46: [ALLY, "heavyhorse"] }), 46);
  for (const index of ring(46, 3).concat(ring(46, 4))) {
    assert.ok(!moves.includes(index));
    assert.ok(rings.get(index) >= 60 && rings.get(index) < 70, `hex ${index} previews as empty`);
  }
});

test("inARow is the three hex axes", () => {
  for (const a of HEXES) {
    for (const b of HEXES) {
      const ca = cube(a);
      const cb = cube(b);
      const axis = ca.q === cb.q || ca.r === cb.r || ca.s === cb.s;
      assert.equal(inARow(a, b), axis, `${a.index} and ${b.index}`);
    }
  }
});

// The legacy ring walk is a breadth-first search through empty hexes. This
// oracle is written from that rule alone and compared on random positions.
function oracle(board, origin, steps) {
  const piece = board.pieceAt(origin);
  const reached = new Map([[origin, 0]]);
  const frontier = [origin];
  const moves = new Set();
  const attacks = new Set();
  while (frontier.length) {
    const at = frontier.shift();
    const d = reached.get(at);
    if (d === steps) continue;
    for (const n of neighbors(hexAt(at))) {
      if (reached.has(n.index)) continue;
      reached.set(n.index, d + 1);
      const other = board.pieceAt(n.index);
      if (!other) {
        moves.add(n.index);
        frontier.push(n.index);
      } else if (other.team !== piece.team && other.type.codename !== "mountain") {
        const trumped = piece.type.trump.includes(other.type.codename);
        const repels = other.type.trump.includes(piece.type.codename);
        if (!repels && (trumped || other.type.defence <= piece.type.attack)) attacks.add(n.index);
      }
    }
  }
  const sort = (s) => [...s].sort((a, b) => a - b);
  return { moves: sort(moves), attacks: sort(attacks) };
}

test("melee moves and captures match a breadth-first oracle on random boards", () => {
  const rng = seeded(4);
  const kinds = Object.keys(UNIT_TYPES).filter((k) => k !== "mountain");
  const melee = ["rabble", "spearman", "elephant", "king", "lighthorse", "heavyhorse"];
  for (let trial = 0; trial < 400; trial++) {
    const layout = {};
    for (const hex of HEXES) {
      if (rng() < 0.35) {
        const kind = rng() < 0.15 ? "mountain" : kinds[Math.floor(rng() * kinds.length)];
        layout[hex.index] = [rng() < 0.5 ? ALLY : ENEMY, kind];
      }
    }
    const origin = 1 + Math.floor(rng() * 91);
    const kind = melee[trial % melee.length];
    layout[origin] = [ALLY, kind];
    const board = position(layout);
    const type = UNIT_TYPES[kind];

    for (const jump of type.rank === "cavalry" ? [1, 2] : [1]) {
      const steps = jump === 2 ? 2 : type.moveRange;
      const { moves, attacks } = legalActions(board, origin, { jump });
      const expected = oracle(board, origin, steps);
      assert.deepEqual({ moves, attacks }, expected, `trial ${trial}: ${kind} on ${origin}, jump ${jump}`);
    }
  }
});
