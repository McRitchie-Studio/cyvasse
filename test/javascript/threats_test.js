// [unit] The threat map (cyvasse/threats): what one side could reach and what
// it could kill on its next turn, built from the rules' own legalActions.
import { test } from "node:test";
import assert from "node:assert/strict";

import { HEXES, hexAt, distance, neighbors } from "cyvasse/board";
import { UNIT_TYPES } from "cyvasse/units";
import { legalActions } from "cyvasse/rules";
import { threats, outlineEdges } from "cyvasse/threats";

const ME = 1;
const THEM = 0;
const disc = (origin, r) => HEXES.filter((h) => h.index !== origin && distance(hexAt(origin), h) <= r).map((h) => h.index);
const sorted = (set) => [...set].sort((a, b) => a - b);

// A Game-shaped position from { hex: [team, codename] }.
function board(layout) {
  const units = Object.entries(layout).map(([hex, [team, codename]]) => ({ team, hex: Number(hex), type: UNIT_TYPES[codename], status: "alive" }));
  return {
    pieceAt: (hex) => units.find((u) => u.hex === hex),
    teamUnits: (team) => units.filter((u) => u.team === team)
  };
}

test("a lone rabble reaches its whole move range and kills nothing", () => {
  const { reach, kills } = threats(board({ 46: [THEM, "rabble"] }), THEM);
  assert.deepEqual(sorted(reach), disc(46, 3));
  assert.deepEqual(sorted(kills), []);
});

test("only the side asked about is counted", () => {
  const { reach } = threats(board({ 46: [ME, "rabble"] }), THEM);
  assert.equal(reach.size, 0);
});

test("a shooter's line of fire is reach; only a unit it can hurt is a kill", () => {
  // A catapult (attack 3) on 46 fires along the middle row: an elephant
  // (defence 4) on 48 stands in the line of fire but cannot be killed; a
  // rabble (defence 1) on 44 can.
  const position = board({ 46: [THEM, "catapult"], 48: [ME, "elephant"], 44: [ME, "rabble"] });
  const { reach, kills } = threats(position, THEM);
  assert.ok(reach.has(48), "the elephant is within reach");
  assert.ok(!kills.has(48), "but the catapult cannot kill it");
  assert.ok(kills.has(44), "the rabble it can kill");
  assert.deepEqual(sorted(kills), legalActions(position, 46).attacks, "kills are the rules' attacks");
  // The line of fire reaches past where the catapult can move.
  assert.ok(disc(46, 3).every((h) => reach.has(h) || position.pieceAt(h)), "the whole range is reach");
});

test("a cavalry unit threatens through its second jump", () => {
  // A light horse on 46 moves three, then two more: a rabble five away is a
  // kill that no single legalActions call from 46 can see.
  const far = HEXES.find((h) => distance(hexAt(46), h) === 5).index;
  const position = board({ 46: [THEM, "lighthorse"], [far]: [ME, "rabble"] });
  assert.ok(!legalActions(position, 46).attacks.includes(far), "not on the first jump");
  const { reach, kills } = threats(position, THEM);
  assert.ok(kills.has(far), "the second jump can take it");
  assert.ok(reach.has(far));
  assert.ok(disc(46, 5).every((h) => reach.has(h)), "reach runs five hexes out");
});

test("a horse that takes the king does not jump on", () => {
  // The king (defence 2) next to a heavy horse (attack 3); a rabble two
  // beyond it is reachable only by jumping on from the king's hex.
  // Mountains wall the horse in on every other side.
  const layout = { 46: [THEM, "heavyhorse"], 47: [ME, "king"], 49: [ME, "rabble"] };
  for (const h of [45, 35, 36, 56, 57]) layout[h] = [THEM, "mountain"];
  const position = board(layout);
  const unguarded = board({ ...layout, 47: [ME, "rabble"] });
  assert.ok(threats(unguarded, THEM).kills.has(49), "past a rabble the second jump goes on");
  const { kills } = threats(position, THEM);
  assert.ok(kills.has(47), "the king can be taken");
  assert.ok(!kills.has(49), "nothing is taken after the king falls");
});

// The board's hexes laid out as the board controller draws them (W = 60,
// pointy-top, rows offset by half a hex), at full size so neighbours share
// their corners exactly.
const W = 60;
const H = W * 2 / Math.sqrt(3);
const POLYGONS = new Map(HEXES.map((hex) => {
  const cx = (11 - hex.size) * W / 2 + (hex.x - 0.5) * W;
  const cy = H / 2 + (hex.y - 1) * H * 0.75;
  const corners = [[0, -H / 2], [W / 2, -H / 4], [W / 2, H / 4], [0, H / 2], [-W / 2, H / 4], [-W / 2, -H / 4]];
  return [hex.index, corners.map(([dx, dy]) => [cx + dx, cy + dy])];
}));
// The pairs (inside, board hex outside) across the region's boundary, by
// the board's own neighbour table: one outline edge each, and no more.
const boundaryPairs = (region) => [...region].flatMap((i) => neighbors(hexAt(i)).filter((n) => !region.has(n.index)));

test("the outline runs only between a region hex and a board hex outside it", () => {
  assert.deepEqual(outlineEdges(new Set(), POLYGONS), [], "no region, no outline");
  assert.deepEqual(outlineEdges(new Set(HEXES.map((h) => h.index)), POLYGONS), [], "the whole board has no outline: its rim is never drawn");
  assert.equal(outlineEdges(new Set([46]), POLYGONS).length, 6, "a lone hex in the middle is ringed");

  // Hex 1 is a corner: only the edges facing its board neighbours are drawn.
  const corner = outlineEdges(new Set([1]), POLYGONS);
  assert.equal(corner.length, neighbors(hexAt(1)).length);
  assert.ok(corner.length < 6, "the corner's rim edges are left out");

  // The computer's five rows reach the rim on three sides; only the line
  // where they meet the rest of the board is drawn.
  for (const region of [new Set(HEXES.filter((h) => h.index <= 40).map((h) => h.index)), new Set([1, ...disc(46, 3), 91])]) {
    assert.equal(outlineEdges(region, POLYGONS).length, boundaryPairs(region).length);
  }
});
