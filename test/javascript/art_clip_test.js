// [unit] The piece art's clip on the board (cyvasse/art_clip): cut along its
// hex's right, lower-right and lower-left sides, free over the upper-right,
// upper-left and left ones (task cyvasse-piece-art-overlap).
import { test } from "node:test";
import assert from "node:assert/strict";

import { HEX_SIDES, CLIPPED_SIDES, FREE_SIDES, ART_REACH, hexCorners, artClipCorners, pointsAttribute } from "cyvasse/art_clip";

// The board's hex (cyvasse_game_controller: W = 60, H = W * 2 / sqrt 3).
const W = 60;
const H = W * 2 / Math.sqrt(3);
const SCALE = 0.97;
const hex = hexCorners(W, H, SCALE);
const clip = artClipCorners(W, H, { scale: SCALE });

// Even-odd ray cast; a point on the boundary may fall either way, so the
// probes below stand clear of it.
function inside([px, py], polygon) {
  let hit = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const [xi, yi] = polygon[i];
    const [xj, yj] = polygon[j];
    if ((yi > py) !== (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) hit = !hit;
  }
  return hit;
}

// The midpoint of a side, and the unit normal pointing out of the hex.
function side(name) {
  const i = HEX_SIDES.indexOf(name);
  const [ax, ay] = hex[i];
  const [bx, by] = hex[(i + 1) % 6];
  const length = Math.hypot(bx - ax, by - ay);
  // Clockwise corners on a y-down screen: the outward normal is (dy, -dx).
  return { mid: [(ax + bx) / 2, (ay + by) / 2], out: [(by - ay) / length, -(bx - ax) / length], ends: [hex[i], hex[(i + 1) % 6]] };
}
const step = ([x, y], [nx, ny], d) => [x + nx * d, y + ny * d];

test("the six sides split three clipped, three free", () => {
  assert.deepEqual([...CLIPPED_SIDES, ...FREE_SIDES].sort(), [...HEX_SIDES].sort());
  assert.deepEqual([...CLIPPED_SIDES].sort(), ["lower-left", "lower-right", "right"]);
  assert.deepEqual([...FREE_SIDES].sort(), ["left", "upper-left", "upper-right"]);
});

test("hexCorners is the board's pointy-top hex, clockwise from the top", () => {
  const full = hexCorners(W, H);
  assert.deepEqual(full[0], [0, -H / 2]);
  assert.deepEqual(full[1], [W / 2, -H / 4]);
  assert.deepEqual(full[3], [0, H / 2]);
  assert.deepEqual(full[5], [-W / 2, -H / 4]);
  assert.equal(pointsAttribute(hexCorners(W, H, SCALE)), "0.00,-33.60 29.10,-16.80 29.10,16.80 0.00,33.60 -29.10,16.80 -29.10,-16.80");
});

test("the clip runs exactly along the right, lower-right and lower-left sides", () => {
  // Its first four corners are the hex's upper-right, lower-right, bottom and
  // lower-left corners, so those three sides are sides of the clip itself.
  assert.deepEqual(clip.slice(0, 4), [hex[1], hex[2], hex[3], hex[4]]);
  for (const name of CLIPPED_SIDES) {
    const { mid, out } = side(name);
    assert.ok(inside(step(mid, out, -0.25), clip), `just inside the ${name} side is kept`);
    assert.ok(!inside(step(mid, out, 0.25), clip), `just past the ${name} side is cut`);
    assert.ok(!inside(step(mid, out, 20), clip), `well past the ${name} side is cut`);
  }
});

test("the clip frees exactly the upper-right, upper-left and left sides, out to ART_REACH", () => {
  for (const name of FREE_SIDES) {
    const { mid, out } = side(name);
    for (const d of [0.25, 5, 0.9 * ART_REACH * H]) {
      assert.ok(inside(step(mid, out, d), clip), `${d.toFixed(1)} past the ${name} side is kept`);
    }
    assert.ok(!inside(step(mid, out, 2 * ART_REACH * H), clip), `the ${name} side's freedom ends`);
  }
  // Over the top corner, the whole reach.
  assert.ok(inside([0, hex[0][1] - 0.95 * ART_REACH * H], clip));
  assert.ok(!inside([0, hex[0][1] - 1.05 * ART_REACH * H], clip));
});

test("the freed art never enters the hex to the right or the hexes below", () => {
  // Neighbour centres, and points just inside each neighbour near the shared corners.
  const rightHex = hexCorners(W, H, SCALE).map(([x, y]) => [x + W, y]);
  const lowerLeft = hexCorners(W, H, SCALE).map(([x, y]) => [x - W / 2, y + 0.75 * H]);
  const lowerRight = hexCorners(W, H, SCALE).map(([x, y]) => [x + W / 2, y + 0.75 * H]);
  const leftHex = hexCorners(W, H, SCALE).map(([x, y]) => [x - W, y]);
  for (const [name, polygon] of Object.entries({ right: rightHex, "lower-left": lowerLeft, "lower-right": lowerRight })) {
    const [cx, cy] = [polygon[0][0], polygon[0][1] + H * SCALE / 2];
    assert.ok(!inside([cx, cy], clip), `${name} neighbour's centre`);
    // Every point of the neighbour, sampled: none is in the clip, but for a
    // hair along the side shared with this hex.
    for (let t = 0.02; t < 1; t += 0.04) {
      for (let u = 0.02; u < 1; u += 0.04) {
        const x = cx + (t - 0.5) * W * 0.9;
        const y = cy + (u - 0.5) * H * 0.9;
        if (inside([x, y], polygon)) assert.ok(!inside([x, y], clip), `(${x.toFixed(1)}, ${y.toFixed(1)}) in the ${name} neighbour`);
      }
    }
  }
  // The left neighbour's lower-right side continues the clip's lower-left
  // edge, so the art in it stays above that line: its upper-right part is
  // free, its bottom corner is not.
  assert.ok(inside([leftHex[1][0] - 2, leftHex[1][1]], clip), "the left neighbour's upper-right corner is reached");
  assert.ok(!inside([leftHex[3][0], leftHex[3][1] - 2], clip), "the left neighbour's bottom corner is not");
});
