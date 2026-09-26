// What a selected unit may do: where it can move and what it can capture.
//
// Ported from the legacy ring walks, amcritchie/Cyvasse
// app/assets/javascripts/hexRange/{range,setMoveRings,setRangeRings,check}.js.
// The legacy code wrote a two-digit "ring" onto every hex, and both the rules
// and the ripple animation read it back. The encoding is kept verbatim, so the
// board can animate from the same numbers the rules decided on:
//
//   ring = code * 10 + step      step = distance - 1 (0-based)
//
//   Move rings                        Projectile ("range") rings
//   9   the selected unit             9   the shooter
//   1x  empty: move here              1x  line of fire passes (empty, friend,
//   2x  dragon flies over (friend,        or an enemy it cannot hurt)
//       mountain)                     2x  an enemy it can hit
//   3x  dragon captures and flies on  3x  shadow: behind a mountain
//   4x  capture here, path ends       4x  a mountain square in the line of fire
//   5x  blocked                       (rings only reach attackRange)
//   6x  7x 8x  a cavalry unit's first jump seen two hexes further: the
//       same as 1x 4x 5x, drawn as outlines to preview the second jump
//
// A hex joins ring `step` when a neighbour holds a ring the walk may pass
// through at `step - 1`: 1x or 6x for everyone, plus 2x and 3x for the dragon.

import { hexAt, neighbors } from "cyvasse/board";
import { potentialRange } from "cyvasse/potential_range";

const SELECTED = 9;
const UNRINGED = 8;

// The legal actions for the unit on `originIndex`.
//
//   position  anything with pieceAt(hexIndex) -> { team, type } | undefined
//   jump      1, or 2 for a cavalry unit's second jump
//
// Returns { moves, attacks, rings, rangeRings }: sorted hex indices, and the
// two ring maps (hexIndex -> ring) for drawing.
export function legalActions(position, originIndex, { jump = 1 } = {}) {
  const origin = hexAt(originIndex);
  const piece = position.pieceAt(originIndex);
  if (!origin || !piece) throw new Error(`no unit on hex ${originIndex}`);
  const type = piece.type;

  const rings = new Map([[originIndex, SELECTED]]);
  const rangeRings = new Map([[originIndex, SELECTED]]);
  const walker = { position, piece, type, rings };

  const potentialMove = sorted(potentialRange(origin, type.moveRange, { dragon: type.codename === "dragon" }));

  if (type.rank === "cavalry" && jump === 1) {
    const preview = sorted(potentialRange(origin, type.moveRange + 2));
    walkMoveRings(walker, preview, type.moveRange + 2, { preview: true });
  }
  const steps = type.rank === "cavalry" && jump === 2 ? 2 : type.moveRange;
  walkMoveRings(walker, potentialMove, steps);

  const ringOf = (index) => rings.get(index) ?? UNRINGED;
  const moves = potentialMove.filter((i) => ringOf(i) >= 10 && ringOf(i) <= 19);

  let attacks;
  if (type.rank !== "range") {
    attacks = potentialMove.filter((i) => ringOf(i) >= 30 && ringOf(i) <= 49);
  } else {
    const potentialShot = sorted(potentialRange(origin, type.attackRange));
    walkRangeRings({ position, piece, type, origin, rings: rangeRings }, potentialShot);
    attacks = potentialShot.filter((i) => {
      const ring = rangeRings.get(i) ?? UNRINGED;
      return ring >= 20 && ring <= 29;
    });
  }

  return { moves, attacks, rings, rangeRings };
}

// The move rings (setMoveRings.js). With `preview` it is CavalryMoveRings,
// which runs the same walk two hexes further and writes 6x/7x/8x in place of
// 1x/4x/5x, so the preview never counts as a legal move.
const PREVIEW_CODE = { 1: 6, 4: 7, 5: 8 };

function walkMoveRings({ position, piece, type, rings }, candidates, steps, { preview = false } = {}) {
  const locked = new Set();
  const dragon = type.codename === "dragon";

  for (let step = 0; step < steps; step++) {
    const passable = [step + 9, step + 19, step + 29, step + 59];
    for (const index of candidates.filter((i) => !locked.has(i))) {
      const hasPath = neighbors(hexAt(index)).some((n) => passable.includes(rings.get(n.index)));
      if (!hasPath) continue;

      const occupant = position.pieceAt(index);
      const code = dragon ? dragonCode(piece, occupant) : standardCode(piece, type, occupant);
      rings.set(index, step + (preview ? PREVIEW_CODE[code] : code) * 10);
      locked.add(index);
    }
  }
}

function standardCode(piece, type, occupant) {
  if (!occupant) return 1;
  if (occupant.type.codename === "mountain" || occupant.team === piece.team) return 5;

  let code = occupant.type.defence > type.attack ? 5 : 4;
  if (type.trump.includes(occupant.type.codename)) code = 4;
  if (occupant.type.trump.includes(type.codename)) code = 5;
  return code;
}

function dragonCode(piece, occupant) {
  if (!occupant) return 1;
  if (occupant.type.codename === "mountain" || occupant.team === piece.team) return 2;
  if (occupant.type.rank === "range" || occupant.type.codename === "dragon") {
    return ["trebuchet", "catapult"].includes(occupant.type.codename) ? 5 : 4;
  }
  return 3;
}

// The projectile rings (setRangeRings.js). Shots pass over empty hexes,
// friends and enemies alike; a mountain throws a shadow one ring deep, and
// the shadow deepens ring by ring.
function walkRangeRings({ position, piece, type, origin, rings }, candidates) {
  const locked = new Set();
  const ringsOfNeighbors = (index) => neighbors(hexAt(index)).map((n) => rings.get(n.index));

  for (let step = 0; step < type.attackRange; step++) {
    for (const index of candidates.filter((i) => !locked.has(i))) {
      const around = ringsOfNeighbors(index);

      if (around.includes(step + 9) || around.includes(step + 19)) {
        const occupant = position.pieceAt(index);
        let ring = step + 10;
        if (occupant?.type.codename === "mountain") {
          ring = step + (inARow(origin, hexAt(index)) ? 40 : 30);
        } else if (occupant && occupant.team !== piece.team) {
          ring = step + (occupant.type.defence > type.attack ? 10 : 20);
          if (type.trump.includes(occupant.type.codename)) ring = step + 20;
          if (occupant.type.trump.includes(type.codename)) ring = step + 10;
        }
        if (around.includes(step + 29)) ring = step + 30;
        rings.set(index, ring);
        locked.add(index);
      } else if (around.includes(step + 39) || around.includes(step + 49)) {
        rings.set(index, step + 30);
        locked.add(index);
      }
    }
  }
}

// Whether two hexes share a row or a diagonal (hexRange/check.js).
export function inARow(hex1, hex2) {
  if (hex1.y === hex2.y) return true;

  const sizeOfRow = (y) => (y >= 1 && y <= 11 ? (y < 7 ? y + 5 : 17 - y) : undefined);
  const distance = Math.abs(hex1.y - hex2.y);
  let constantUp = 0;
  let constantDown = 0;
  for (let i = 0; i < distance; i++) {
    if (sizeOfRow(hex1.y + i) < sizeOfRow(hex1.y + i + 1)) constantDown += 1;
    if (sizeOfRow(hex1.y - i) > sizeOfRow(hex1.y - i - 1)) constantUp += 1;
  }

  const candidates = [
    [hex1.x - constantUp, hex1.y - distance],
    [hex1.x + distance - constantUp, hex1.y - distance],
    [hex1.x + constantDown, hex1.y + distance],
    [hex1.x - distance + constantDown, hex1.y + distance]
  ];
  return candidates.some(([x, y]) => x === hex2.x && y === hex2.y);
}

function sorted(set) {
  return [...set].sort((a, b) => a - b);
}
