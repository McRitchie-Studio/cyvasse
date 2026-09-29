// The board's hex edges, for the highlight borders the controller draws.
//
// Every edge is drawn once, over both hexes it separates, in the colour of
// whichever highlight owns it (EDGE_PRIORITY), so two neighbouring
// highlights never split a shared edge half and half.
//
//   perimeter(region)          the edges round a set of hexes: in the set on
//                              one side, off it (or off the board) on the other
//   resolveEdges(claims, rim)  one owner per edge, by EDGE_PRIORITY

import { HEXES, cube } from "cyvasse/board";

// Side i runs from corner i to corner i + 1 of a pointy-top hex, corners
// clockwise from the top: north-east, east, south-east, south-west, west,
// north-west, as axial (q, r) steps.
const STEPS = [[1, -1], [1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1]];

const BY_AXIAL = new Map(HEXES.map((hex) => {
  const { q, r } = cube(hex);
  return [`${q},${r}`, hex.index];
}));

const SIDE_NEIGHBORS = new Map(HEXES.map((hex) => {
  const { q, r } = cube(hex);
  return [hex.index, STEPS.map(([dq, dr]) => BY_AXIAL.get(`${q + dq},${r + dr}`) ?? null)];
}));

// The hex across each of a hex's six sides, or null at the board's rim.
export function sideNeighbors(index) {
  return SIDE_NEIGHBORS.get(index);
}

// One key per edge, the same from either side: "<hex>:<side>" of the lower hex.
export function edgeKey(index, side) {
  const other = SIDE_NEIGHBORS.get(index)[side];
  return other !== null && other < index ? `${other}:${(side + 3) % 6}` : `${index}:${side}`;
}

// Every edge on the board, once: { key, hex, side, other } (other null at the rim).
export const EDGES = Object.freeze(HEXES.flatMap((hex) =>
  SIDE_NEIGHBORS.get(hex.index)
    .map((other, side) => ({ key: `${hex.index}:${side}`, hex: hex.index, side, other }))
    .filter(({ other }) => other === null || other > hex.index)
));

// The keys of the edges round `region` (a Set of hex indexes): shared edges
// inside it are left out; the board's rim counts as outside.
export function perimeter(region) {
  const keys = new Set();
  for (const index of region) {
    const neighbors = SIDE_NEIGHBORS.get(index);
    if (!neighbors) continue;
    neighbors.forEach((other, side) => {
      if (other === null || !region.has(other)) keys.add(edgeKey(index, side));
    });
  }
  return keys;
}

// Who owns a shared edge, highest first. "ring" (a plain move ring) draws
// nothing: its hexes keep their own thin edges, and nothing beneath crosses.
export const EDGE_PRIORITY = Object.freeze([
  "selected",
  "target", "ghost-7", "ghost-6", "ghost-8", "field", "blocked", "ring",
  "last-move",
  "danger",
  "perimeter",
  "team-1", "team-0"
]);

const RANK = new Map(EDGE_PRIORITY.map((kind, i) => [kind, i]));

function best(kinds) {
  let top = null;
  for (const kind of kinds) {
    if (kind && (top === null || RANK.get(kind) < RANK.get(top))) top = kind;
  }
  return top;
}

// The border a hex claims for all six of its edges, from its classes (a Set)
// and the team of the unit on it; null for none. A last-moved unit's hex
// carries its team's edge; an empty one the last move's orange.
export function hexClaim(classes, { team = null, ghost = null } = {}) {
  const kinds = [];
  if (classes.has("is-selected")) kinds.push("selected");
  if (classes.has("is-target")) kinds.push("target");
  if (classes.has("is-ghost") && ghost) kinds.push(`ghost-${ghost}`);
  if (classes.has("is-field")) kinds.push("field");
  if (classes.has("is-blocked")) kinds.push("blocked");
  if (classes.has("is-lit") || classes.has("is-move") || classes.has("is-attack")) kinds.push("ring");
  if (classes.has("is-last-move")) kinds.push(team === null ? "last-move" : `team-${team}`);
  if (classes.has("is-danger")) kinds.push("danger");
  return best(kinds);
}

// Map of edge key -> owning kind, for every edge anything claims. `claims`
// maps a hex index to its hexClaim; `rim` is a perimeter() key set, drawn
// as "perimeter" where no hex claim outranks it.
export function resolveEdges(claims, rim = new Set()) {
  const owners = new Map();
  for (const { key, hex, other } of EDGES) {
    const owner = best([claims.get(hex), other === null ? null : claims.get(other), rim.has(key) ? "perimeter" : null]);
    if (owner) owners.set(key, owner);
  }
  return owners;
}
