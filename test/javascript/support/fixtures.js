// Shared helpers for the engine's unit tests.
import { UNIT_TYPES } from "cyvasse/units";

// A position from { hexIndex: [team, codename] }, shaped like a Game for
// legalActions (anything with pieceAt).
export function position(layout) {
  const pieces = new Map(
    Object.entries(layout).map(([hex, [team, codename]]) => [Number(hex), { team, type: UNIT_TYPES[codename] }])
  );
  return { pieceAt: (hex) => pieces.get(hex), pieces };
}

// mulberry32: a small seeded source so every run replays the same games.
export function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
