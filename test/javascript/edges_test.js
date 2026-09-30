// [unit] The board's edges (cyvasse/edges): the perimeter round a set of
// hexes, and the one highlight that owns each shared edge.
import { test } from "node:test";
import assert from "node:assert/strict";

import { HEXES, hexAt, neighbors, distance } from "cyvasse/board";
import { UNIT_TYPES } from "cyvasse/units";
import { threats } from "cyvasse/threats";
import { sideNeighbors, edgeKey, EDGES, perimeter, EDGE_PRIORITY, hexClaim, resolveEdges, threatRims, outerRim, PERIMETER_STYLE } from "cyvasse/edges";

const disc = (origin, r) => new Set(HEXES.filter((h) => distance(hexAt(origin), h) <= r).map((h) => h.index));
const sidesOf = (index) => [0, 1, 2, 3, 4, 5].map((side) => edgeKey(index, side));
const RIM = EDGES.filter((e) => e.other === null).length;

test("each hex's six sides are the legacy neighbour table, and a shared side is one edge", () => {
  for (const hex of HEXES) {
    const across = sideNeighbors(hex.index);
    assert.equal(across.length, 6);
    const legacy = neighbors(hex).map((h) => h.index).sort((a, b) => a - b);
    assert.deepEqual(across.filter((i) => i !== null).sort((a, b) => a - b), legacy, `hex ${hex.index}`);
    across.forEach((other, side) => {
      if (other === null) return;
      assert.equal(sideNeighbors(other)[(side + 3) % 6], hex.index, "the far hex's opposite side comes back");
      assert.equal(edgeKey(hex.index, side), edgeKey(other, (side + 3) % 6), "one key from either side");
    });
  }
  const keys = new Set(EDGES.map((e) => e.key));
  assert.equal(keys.size, EDGES.length, "every edge once");
  assert.equal(EDGES.length, (91 * 6 + RIM) / 2);
  assert.equal(RIM, 6 * 3 + 24 * 2, "six corner hexes with three rim sides, 24 with two");
  for (const hex of HEXES) assert.equal(new Set(sidesOf(hex.index)).size, 6);
});

test("a lone hex is outlined on all six sides", () => {
  assert.deepEqual([...perimeter(new Set([46]))].sort(), sidesOf(46).sort());
});

test("a filled disc leaves out every shared interior edge", () => {
  const region = disc(46, 1);
  const rim = perimeter(region);
  assert.equal(rim.size, 18);
  for (const key of sidesOf(46)) assert.ok(!rim.has(key), `the centre's edge ${key} is interior`);
});

test("a hole is outlined on its inside too", () => {
  // Radius two round 46, its centre left out: 30 edges round the outside,
  // six round the hole.
  const region = disc(46, 2);
  region.delete(46);
  const rim = perimeter(region);
  assert.equal(rim.size, 30 + 6);
  for (const key of sidesOf(46)) assert.ok(rim.has(key), `the hole's edge ${key}`);
});

test("the board's rim counts as outside", () => {
  // Hex 1 is the top-left corner: three of its sides face off the board.
  const corner = perimeter(new Set([1]));
  assert.equal(corner.size, 6);
  assert.equal(sideNeighbors(1).filter((i) => i === null).length, 3);
  const whole = perimeter(new Set(HEXES.map((h) => h.index)));
  assert.equal(whole.size, RIM, "the whole board: its rim alone");
  assert.equal(perimeter(new Set()).size, 0);
});

test("every perimeter edge has the region on exactly one side", () => {
  // Scattered shapes: every third hex, one half of the board, a band.
  const shapes = [
    new Set(HEXES.filter((h) => h.index % 3 === 0).map((h) => h.index)),
    new Set(HEXES.filter((h) => h.index <= 45).map((h) => h.index)),
    new Set(HEXES.filter((h) => h.y >= 5 && h.y <= 7).map((h) => h.index))
  ];
  for (const region of shapes) {
    const rim = perimeter(region);
    for (const { key, hex, other } of EDGES) {
      const inside = [hex, other].filter((i) => i !== null && region.has(i)).length;
      assert.equal(rim.has(key), inside === 1, `edge ${key}`);
    }
  }
});

test("the priority runs selection, rings, danger, perimeter; the last move draws no edge", () => {
  const order = ["selected", "target", "ring", "danger", "perimeter", "perimeter-ranged"].map((k) => EDGE_PRIORITY.indexOf(k));
  assert.ok(order.every((rank, i) => rank >= 0 && (i === 0 || rank > order[i - 1])), `${EDGE_PRIORITY}`);
  for (const gone of ["last-move", "team-0", "team-1"]) assert.equal(EDGE_PRIORITY.includes(gone), false, gone);
});

test("a hex claims its highest highlight", () => {
  const claim = (names, extra) => hexClaim(new Set(names), extra);
  assert.equal(claim([]), null);
  assert.equal(claim(["is-last-move"]), null, "the last move is a glow, not an edge");
  assert.equal(claim(["is-last-move", "has-unit"]), null, "a moved unit wears no ring either");
  assert.equal(claim(["is-last-move", "is-danger"]), "danger");
  assert.equal(claim(["is-field", "is-lit"]), "field");
  assert.equal(claim(["is-sunken"]), "ring", "a sunken hex is part of the ring: no perimeter crosses it");
  assert.equal(claim(["is-ghost"], { ghost: 7 }), "ghost-7");
  assert.equal(claim(["is-move", "is-danger", "is-selected"]), "selected");
  assert.equal(claim(["is-threatened"]), null, "reach alone claims nothing: only its perimeter is drawn");
});

test("the last move leaves the threat outline as it is, whoever moved", () => {
  // 46 the hex a unit left, 47 where it stands now, both on the outline's rim.
  const rim = perimeter(disc(46, 1));
  const claims = new Map();
  for (const hex of [46, 47]) {
    const kind = hexClaim(new Set(["is-last-move", ...(hex === 47 ? ["has-unit"] : [])]));
    if (kind) claims.set(hex, kind);
  }
  assert.equal(claims.size, 0);
  const owners = resolveEdges(claims, rim);
  assert.deepEqual([...owners.keys()].sort(), [...rim].sort(), "the rim, and nothing else");
  assert.ok([...owners.values()].every((k) => k === "perimeter"));
});

test("one owner per edge, the highest claim on either side or the perimeter", () => {
  const region = disc(46, 1);
  const rim = perimeter(region);
  const claims = new Map([[46, "danger"], [45, "selected"], [47, "ring"]]);
  const owners = resolveEdges(claims, rim);
  const across = (a, b) => edgeKey(a, sideNeighbors(a).indexOf(b));
  assert.equal(owners.get(across(46, 45)), "selected", "the selection beats danger");
  assert.equal(owners.get(across(46, 47)), "ring", "a move ring beats danger");
  // 45 is in the region: its outer edges are perimeter, but its own
  // selection claim owns them.
  for (const key of sidesOf(45)) assert.equal(owners.get(key), "selected");
  for (const key of sidesOf(47)) assert.equal(owners.get(key), "ring", "nothing beneath crosses a ring");
  for (const key of rim) {
    const { hex, other } = EDGES.find((e) => e.key === key);
    if ([hex, other].some((i) => claims.has(i) && ["selected", "ring"].includes(claims.get(i)))) continue;
    assert.equal(owners.get(key), "perimeter", `perimeter edge ${key}`);
  }
  // Interior edges of the region with no claim stay undrawn.
  const interior = EDGES.filter((e) => region.has(e.hex) && region.has(e.other) && !claims.has(e.hex) && !claims.has(e.other));
  assert.ok(interior.length > 0);
  for (const { key } of interior) assert.equal(owners.has(key), false, `interior edge ${key}`);
});

test("the default style is one solid rim round both groups' areas together", () => {
  assert.equal(PERIMETER_STYLE, "single");
  const regions = { melee: disc(46, 1), ranged: disc(47, 1) };
  const { solid, dashed } = threatRims(regions);
  assert.deepEqual([...solid].sort(), [...perimeter(new Set([...regions.melee, ...regions.ranged]))].sort());
  assert.equal(dashed.size, 0);
  assert.deepEqual([...threatRims({ melee: new Set(), ranged: regions.ranged }).solid].sort(), [...perimeter(regions.ranged)].sort(), "one group alone is solid too");
  assert.ok([...resolveEdges(new Map(), solid, dashed).values()].every((k) => k === "perimeter"));
});

test("dual style: melee-only edges solid, ranged-only dashed, shared edges solid", () => {
  // Two overlapping discs share a stretch of outer rim along the board's edge.
  const { solid: melee, dashed: ranged } = threatRims({ melee: disc(46, 1), ranged: disc(47, 1) }, "dual");
  assert.deepEqual([...melee].sort(), [...perimeter(disc(46, 1))].sort());
  assert.deepEqual([...ranged].sort(), [...perimeter(disc(47, 1))].sort());
  const shared = [...melee].filter((k) => ranged.has(k));
  const meleeOnly = [...melee].filter((k) => !ranged.has(k));
  const rangedOnly = [...ranged].filter((k) => !melee.has(k));
  assert.ok(shared.length > 0 && meleeOnly.length > 0 && rangedOnly.length > 0);

  const owners = resolveEdges(new Map(), melee, ranged);
  for (const key of meleeOnly) assert.equal(owners.get(key), "perimeter", `melee edge ${key}`);
  for (const key of rangedOnly) assert.equal(owners.get(key), "perimeter-ranged", `ranged edge ${key}`);
  for (const key of shared) assert.equal(owners.get(key), "perimeter", `shared edge ${key}`);
  assert.equal(owners.size, new Set([...melee, ...ranged]).size, "nothing else is drawn");

  assert.ok([...resolveEdges(new Map(), new Set(), ranged).values()].every((k) => k === "perimeter-ranged"), "ranged alone is all dashed");
  const edge = [...disc(47, 1)].flatMap((hex) => sidesOf(hex).filter((k) => ranged.has(k)).map((key) => ({ hex, key })))[0];
  assert.equal(resolveEdges(new Map([[edge.hex, "danger"]]), new Set(), ranged).get(edge.key), "danger", "danger still outranks a ranged edge");
});

test("the threat outline traces only the outer rim, never a hole inside it", () => {
  // A ring of hexes round 46: 46 itself is a hole (a unit nobody can take).
  const ring = new Set([...disc(46, 1)].filter((h) => h !== 46));
  assert.ok(sidesOf(46).every((k) => perimeter(ring).has(k)), "perimeter() alone traces the hole");
  const outer = outerRim(ring);
  assert.deepEqual([...outer].sort(), [...perimeter(disc(46, 1))].sort());
  for (const style of ["single", "dual"]) {
    const { solid, dashed } = threatRims({ melee: ring, ranged: ring }, style);
    for (const key of sidesOf(46)) assert.ok(!solid.has(key) && !dashed.has(key), `${style}: no edge round the hole`);
  }
  // A gap that reaches the board's rim is outside, not a hole.
  const corner = new Set([...disc(1, 2)].filter((h) => h !== 1));
  assert.deepEqual([...outerRim(corner)].sort(), [...perimeter(corner)].sort());
});

// Alex's screenshot (2026-09-29): the computer's elephant has just moved
// 48 -> 58, into its own threat area; your elephant on 59 is in danger. The
// moved unit's hex drew a red ring of its own (its team edge, the same red as
// the threat outline) inside the area, so the outline looked to box it.
test("a last-moved enemy unit inside the threat area draws no ring of its own", () => {
  const units = [
    [0, "catapult", 36], [0, "king", 1], [0, "elephant", 58], [0, "rabble", 25],
    [1, "king", 91], [1, "elephant", 59], [1, "rabble", 70]
  ].map(([team, codename, hex]) => ({ team, hex, type: UNIT_TYPES[codename], status: "alive" }));
  const position = { pieceAt: (hex) => units.find((u) => u.hex === hex), teamUnits: (team) => units.filter((u) => u.team === team) };
  const found = threats(position, 0);
  const region = new Set([...found.reach, ...found.units]);
  assert.ok(region.has(58) && region.has(48), "the elephant and the hex it left are inside the area");
  const { solid, dashed } = threatRims({ melee: region, ranged: new Set() });

  const claims = new Map();
  for (const [hex, classes] of [[48, ["is-last-move"]], [58, ["is-last-move", "has-unit"]], [59, ["has-unit", "is-danger"]]]) {
    const kind = hexClaim(new Set(classes));
    if (kind) claims.set(hex, kind);
  }
  const owners = resolveEdges(claims, solid, dashed);
  const across = (a, b) => edgeKey(a, sideNeighbors(a).indexOf(b));
  const stray = sidesOf(58).filter((key) => owners.has(key) && !solid.has(key) && key !== across(58, 59));
  assert.deepEqual(stray.map((key) => `${key}=${owners.get(key)}`), [], "no edge round 58 but the outline and your unit's danger");
  // Every drawn edge is the outline, or your endangered unit's own pulse.
  for (const [key, kind] of owners) {
    assert.ok(kind === "perimeter" || (kind === "danger" && sidesOf(59).includes(key)), `edge ${key} is ${kind}`);
  }
});
