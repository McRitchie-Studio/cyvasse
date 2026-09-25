// The eleven Cyvasse unit types and the nineteen-piece army.
//
// Ported from the legacy factory, amcritchie/Cyvasse
// app/assets/javascripts/LoadFactory/createUnits.js. Where the Ruby models
// (app/models/units/*.rb) disagree with the factory, the factory wins: it is
// what the browser actually played with. The Ruby files carried display
// strings ("2 + 2", "Moves in a straight line") and a stale flank column; the
// numbers below are the ones every legacy move was computed from.
//
// `rank` keeps the legacy spelling of the vanguard ("vangaurd") out of the
// data: nothing ever branched on it, so it is written correctly here.

export const UNIT_TYPES = Object.freeze({
  rabble: unit("rabble", "Rabble", "vanguard", { attack: 1, defence: 1, moveRange: 3, attackRange: 0, flank: 2, trump: [] }),
  spearman: unit("spearman", "Spearman", "vanguard", { attack: 2, defence: 2, moveRange: 2, attackRange: 0, flank: 1, trump: ["lighthorse"] }),
  elephant: unit("elephant", "Elephant", "vanguard", { attack: 4, defence: 4, moveRange: 3, attackRange: 0, flank: 1, trump: [] }),
  lighthorse: unit("lighthorse", "Light Horse", "cavalry", { attack: 2, defence: 2, moveRange: 3, attackRange: 0, flank: 1, trump: [] }),
  heavyhorse: unit("heavyhorse", "Heavy Horse", "cavalry", { attack: 3, defence: 3, moveRange: 2, attackRange: 0, flank: 1, trump: [] }),
  crossbowman: unit("crossbowman", "Crossbowman", "range", { attack: 2, defence: 1, moveRange: 1, attackRange: 2, flank: 0, trump: ["elephant"] }),
  trebuchet: unit("trebuchet", "Trebuchet", "range", { attack: 1, defence: 1, moveRange: 0, attackRange: 3, flank: 0, trump: ["dragon"] }),
  catapult: unit("catapult", "Catapult", "range", { attack: 3, defence: 1, moveRange: 2, attackRange: 3, flank: 0, trump: ["dragon"] }),
  dragon: unit("dragon", "Dragon", "unique", { attack: 5, defence: 5, moveRange: 10, attackRange: 0, flank: 0, trump: [] }),
  king: unit("king", "King", "unique", { attack: 2, defence: 2, moveRange: 2, attackRange: 0, flank: 0, trump: [] }),
  mountain: unit("mountain", "Mountain", "mountain", { attack: 9, defence: 9, moveRange: 0, attackRange: 0, flank: 0, trump: [] })
});

// The army, by the legacy data-index (1-based). Every stored setup string
// ("11:39|6:38|...") names units by this index, so the order is load-bearing.
export const ARMY = Object.freeze([
  "rabble", "rabble", "rabble",
  "spearman", "spearman",
  "elephant", "elephant",
  "lighthorse", "lighthorse",
  "heavyhorse", "heavyhorse",
  "crossbowman", "crossbowman",
  "trebuchet",
  "catapult",
  "dragon",
  "king",
  "mountain", "mountain"
]);

export const ARMY_SIZE = ARMY.length;

// The type of the unit at a 1-based army index.
export function typeAt(index) {
  const type = ARMY[index - 1];
  if (!type) throw new RangeError(`no unit at army index ${index}`);
  return UNIT_TYPES[type];
}

function unit(codename, name, rank, stats) {
  return Object.freeze({ codename, name, rank, ...stats, trump: Object.freeze(stats.trump) });
}
