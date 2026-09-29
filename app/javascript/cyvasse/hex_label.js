// What a screen reader hears for each hex of the board (the hex's aria-label),
// and what the status line says about the player's picked unit.
//
// A hex is named by what stands on it ("Your dragon", "Enemy catapult",
// "Mountain") or, when empty, by its legacy index ("Hex 42"): the board has
// no human-readable coordinate scheme of its own. While a unit of the
// player's is picked, each hex adds what a click there would do:
//
//   selected     the picked unit's own hex           "Your dragon, selected"
//   move         a legal move                        "Hex 42, move here"
//   attack       a legal attack                      "Attack enemy catapult"
//   place        setup: an empty hex it may go to    "Hex 60, place here"
//   unreachable  anything else it cannot go to       "Hex 12, unreachable"
//
// The player's other units stay as they are: a click there picks them.

import { PLAYER } from "cyvasse/game";

export function occupantName(unit) {
  if (unit.type.codename === "mountain") return "Mountain";
  return `${unit.team === PLAYER ? "Your" : "Enemy"} ${unit.type.name.toLowerCase()}`;
}

export function hexLabel(index, unit, state = null) {
  const name = unit ? occupantName(unit) : `Hex ${index}`;
  switch (state) {
    case "selected": return `${name}, selected`;
    case "move": return `${name}, move here`;
    case "attack": return unit ? `Attack ${name.charAt(0).toLowerCase()}${name.slice(1)}` : `${name}, attack`;
    case "place": return `${name}, place here`;
    case "unreachable": return `${name}, unreachable`;
    default: return name;
  }
}

// Each hex's state while a unit is picked, as a Map of hex index -> state;
// empty when nothing of the player's is picked. `pieceAt(index)` is the
// game's own lookup; `actions` its { moves, attacks } from the picked hex.
export function hexStates({ hexes, pieceAt, selectedHex = null, actions = null, dropHexes = null }) {
  const states = new Map();
  if (dropHexes) {
    for (const index of dropHexes) states.set(index, "place");
    if (selectedHex != null) states.set(selectedHex, "selected");
    return states;
  }
  if (selectedHex == null || !actions) return states;
  const picked = pieceAt(selectedHex);
  if (!picked || picked.team !== PLAYER) return states;
  const moves = new Set(actions.moves);
  const attacks = new Set(actions.attacks);
  for (const index of hexes) {
    const unit = pieceAt(index);
    if (index === selectedHex) states.set(index, "selected");
    else if (attacks.has(index)) states.set(index, "attack");
    else if (moves.has(index)) states.set(index, "move");
    else if (!(unit && unit.team === PLAYER && unit.type.codename !== "mountain")) states.set(index, "unreachable");
  }
  return states;
}

// The status line's word on the picked unit ("Dragon selected: 4 moves,
// 1 attack."), said through the board's one live region.
export function selectionNote(unit, actions) {
  if (!unit || !actions) return "";
  const count = (n, one) => `${n} ${one}${n === 1 ? "" : "s"}`;
  const moves = actions.moves.length;
  const attacks = actions.attacks.length;
  const options = moves + attacks === 0 ? "no legal moves" : [
    moves ? count(moves, "move") : null,
    attacks ? count(attacks, "attack") : null
  ].filter(Boolean).join(", ");
  return `${unit.type.name} selected: ${options}.`;
}
