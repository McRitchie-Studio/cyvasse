// The 91-hex Cyvasse board.
//
// Eleven rows of pointy-top hexes, 6 wide at the edges and 11 across the
// middle row. Each hex carries the legacy coordinates, because every rule the
// legacy app ran was written against them (LoadFactory/map.js):
//
//   index  1..91, row by row from the top (the legacy data-hexIndex)
//   x      1..size, left to right within the row (data-xPos)
//   y      1..11, top to bottom (data-yPos)
//   size   the row's width (data-size)
//
// The computer's army deploys in rows 1-5 (hexes 1-40); the player's in rows
// 7-11 (hexes 52-91). Row 6 is no man's land.

export const ROWS = 11;
export const HEX_COUNT = 91;

export function rowSize(y) {
  return y < 7 ? y + 5 : 17 - y;
}

export const HEXES = Object.freeze(buildHexes());

const BY_COORD = new Map(HEXES.map((hex) => [coordKey(hex.x, hex.y), hex]));

// The hex at a 1-based index, or undefined off the board.
export function hexAt(index) {
  return HEXES[index - 1];
}

// The hex at legacy (x, y), or undefined off the board.
export function hexAtXY(x, y) {
  return BY_COORD.get(coordKey(x, y));
}

// The legacy neighbour table (goodCode/neighbors.js): the top half, the middle
// row and the bottom half each lean a different way.
export function neighbors(hex) {
  const { x, y, index } = hex;
  let offsets;
  if (index < 41) {
    offsets = [[-1, -1], [0, -1], [1, 0], [-1, 0], [1, 1], [0, 1]];
  } else if (index < 52) {
    offsets = [[-1, -1], [1, 0], [-1, 0], [-1, 1], [0, -1], [0, 1]];
  } else {
    offsets = [[0, -1], [1, -1], [1, 0], [-1, 0], [-1, 1], [0, 1]];
  }
  return offsets.map(([dx, dy]) => hexAtXY(x + dx, y + dy)).filter(Boolean);
}

// The same hex seen from the other side of the table. The legacy app stored
// both armies from the home player's seat and flipped with 92 - index.
export function mirror(index) {
  return HEX_COUNT + 1 - index;
}

export const COMPUTER_ZONE = Object.freeze(range(1, 40));
export const PLAYER_ZONE = Object.freeze(range(52, 91));

export function inPlayerZone(index) {
  return index >= 52 && index <= 91;
}

// Cube coordinates, for distance and drawing. The legacy code never had
// these; the tests use them as an independent oracle for its range walks.
export function cube(hex) {
  // Axial q runs along the row; each row down the top half shifts the row
  // start one step left, and each row down the bottom half one step right.
  const r = hex.y - 6;
  const q = hex.x - 1 - Math.min(0, r) - 5;
  return { q, r, s: -q - r };
}

export function distance(a, b) {
  const ca = cube(a);
  const cb = cube(b);
  return Math.max(Math.abs(ca.q - cb.q), Math.abs(ca.r - cb.r), Math.abs(ca.s - cb.s));
}

function buildHexes() {
  const hexes = [];
  let index = 1;
  for (let y = 1; y <= ROWS; y++) {
    const size = rowSize(y);
    for (let x = 1; x <= size; x++) {
      hexes.push(Object.freeze({ index, x, y, size }));
      index += 1;
    }
  }
  return hexes;
}

function coordKey(x, y) {
  return `${x},${y}`;
}

function range(from, to) {
  const out = [];
  for (let i = from; i <= to; i++) out.push(i);
  return out;
}
