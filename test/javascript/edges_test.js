// [unit] The board's edges (cyvasse/edges): the perimeter round a set of
// hexes, and the one highlight that owns each shared edge.
import { test } from "node:test";
import assert from "node:assert/strict";

import { HEXES, hexAt, neighbors, distance } from "cyvasse/board";
import { sideNeighbors, edgeKey, EDGES, perimeter, EDGE_PRIORITY, hexClaim, resolveEdges, threatRims, PERIMETER_STYLE } from "cyvasse/edges";

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

test("the priority runs selection, rings, last move, danger, perimeter, team", () => {
  const order = ["selected", "target", "ring", "last-move", "danger", "perimeter", "perimeter-ranged", "team-1"].map((k) => EDGE_PRIORITY.indexOf(k));
  assert.ok(order.every((rank, i) => rank >= 0 && (i === 0 || rank > order[i - 1])), `${EDGE_PRIORITY}`);
});

test("a hex claims its highest highlight", () => {
  const claim = (names, extra) => hexClaim(new Set(names), extra);
  assert.equal(claim([]), null);
  assert.equal(claim(["is-last-move"]), "last-move");
  assert.equal(claim(["is-last-move", "has-unit"], { team: 1 }), "team-1", "a moved unit shows its team");
  assert.equal(claim(["is-last-move", "is-danger"], { team: 1 }), "danger");
  assert.equal(claim(["is-field", "is-lit"]), "field");
  assert.equal(claim(["is-ghost"], { ghost: 7 }), "ghost-7");
  assert.equal(claim(["is-move", "is-danger", "is-selected"]), "selected");
  assert.equal(claim(["is-threatened"]), null, "reach alone claims nothing: only its perimeter is drawn");
});

test("the last move's orange owns the edge it shares with a moved unit's team edge, whole", () => {
  // Alex's screenshot: 46 empty and orange, 47 a unit of yours just moved there.
  const shared = edgeKey(46, sideNeighbors(46).indexOf(47));
  const owners = resolveEdges(new Map([[46, "last-move"], [47, "team-1"]]));
  assert.equal(owners.get(shared), "last-move");
  for (const key of sidesOf(47).filter((k) => k !== shared)) assert.equal(owners.get(key), "team-1");
  assert.equal([...owners.values()].filter((k) => k === "last-move").length, 6);
});

test("one owner per edge, the highest claim on either side or the perimeter", () => {
  const region = disc(46, 1);
  const rim = perimeter(region);
  const claims = new Map([[46, "danger"], [45, "selected"], [47, "ring"], [25, "team-0"], [68, "team-1"]]);
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
  // Team edges lose to the perimeter where they meet it.
  const teamOnRim = sidesOf(25).filter((k) => rim.has(k));
  assert.ok(teamOnRim.length > 0, "25 touches the region");
  for (const key of teamOnRim) assert.equal(owners.get(key), "perimeter");
  assert.ok(sidesOf(25).some((k) => owners.get(k) === "team-0"));
  for (const key of sidesOf(68)) assert.equal(owners.get(key), "team-1");
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
