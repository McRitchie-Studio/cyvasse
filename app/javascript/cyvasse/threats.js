// What one side could do on its next turn, for the board's threat outline.
//
// Built only from the rules' own legalActions (cyvasse/rules), so it follows
// whatever the rules decide, trumps and all:
//
//   reach  every hex the side could move to or strike: each unit's moves and
//          attacks, a shooter's whole line of fire (range rings 1x and 2x),
//          and a cavalry unit's second jump from every hex its first could
//          land on
//   kills  the hexes of enemy units the side could actually capture: the
//          attack lists alone, first jump and second
//
// A unit merely within reach is not in `kills` unless the rules let the
// attacker take it.

import { legalActions } from "cyvasse/rules";

// position: anything with pieceAt(hex) and teamUnits(team, "alive") (a Game).
export function threats(position, team) {
  const reach = new Set();
  const kills = new Set();

  for (const unit of position.teamUnits(team, "alive")) {
    if (unit.hex == null) continue;
    const { moves, attacks, rangeRings } = legalActions(position, unit.hex);
    for (const hex of moves) reach.add(hex);
    for (const hex of attacks) {
      reach.add(hex);
      kills.add(hex);
    }
    if (unit.type.rank === "range") {
      for (const [hex, ring] of rangeRings) {
        if (ring >= 10 && ring <= 29) reach.add(hex);
      }
    }
    if (unit.type.rank === "cavalry") {
      for (const landing of [...moves, ...attacks]) {
        const taken = position.pieceAt(landing);
        // Taking the king ends the game: there is no second jump.
        if (taken?.type.codename === "king") continue;
        const after = landedAt(position, unit, landing);
        const second = legalActions(after, landing, { jump: 2 });
        for (const hex of second.moves) reach.add(hex);
        for (const hex of second.attacks) {
          reach.add(hex);
          kills.add(hex);
        }
      }
    }
  }
  return { reach, kills };
}

// The position after `unit` lands on `landing`, capturing whatever stood there.
function landedAt(position, unit, landing) {
  return {
    pieceAt(hex) {
      if (hex === landing) return unit;
      if (hex === unit.hex) return undefined;
      return position.pieceAt(hex);
    }
  };
}

// The edges to outline round `region` (a Set of hex indexes): only those
// between a hex in it and a board hex outside it. An edge on the board's own
// rim faces nothing, so it is never drawn, and the outline marks where the
// reach ends rather than framing the board.
//
// polygons: every board hex's six corners ([x, y] pairs, index => corners),
// drawn at full size so two neighbours share each corner exactly.
export function outlineEdges(region, polygons) {
  const edges = new Map();
  for (const [index, corners] of polygons) {
    corners.forEach((a, i) => {
      const b = corners[(i + 1) % corners.length];
      const key = [a, b].map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).sort().join(" ");
      const edge = edges.get(key) ?? { ends: [a, b], sides: 0, inside: 0 };
      edge.sides += 1;
      if (region.has(index)) edge.inside += 1;
      edges.set(key, edge);
    });
  }
  return [...edges.values()].filter((edge) => edge.sides === 2 && edge.inside === 1).map((edge) => edge.ends);
}
