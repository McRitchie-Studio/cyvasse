import { PLAYER } from "cyvasse/game";
import { inPlayerZone } from "cyvasse/board";

// What a click does to the picked piece. `hex` is null for a click off the
// board. Answers "act", "select", "deselect" or "none" in play, and "place",
// "select", "deselect" or "none" in setup.

export function playIntent({ hex, selectedHex, actions, selectable }) {
  if (hex != null && actions && (actions.moves.includes(hex) || actions.attacks.includes(hex))) return "act";
  if (hex != null && hex !== selectedHex && selectable.includes(hex)) return "select";
  return selectedHex != null ? "deselect" : "none";
}

export function setupIntent({ hex, unit, selectedUnitId }) {
  if (unit?.team === PLAYER) return unit.id === selectedUnitId ? "deselect" : "select";
  if (selectedUnitId && hex != null && !unit && inPlayerZone(hex)) return "place";
  return selectedUnitId ? "deselect" : "none";
}
