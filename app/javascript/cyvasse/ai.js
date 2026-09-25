// The computer opponent (amcritchie/Cyvasse app/assets/javascripts/ai.js).
//
// It is the legacy opponent on purpose: greedy and a little reckless. If any
// unit can capture, it takes the most valuable piece on offer, the king above
// all. Otherwise it picks a unit at random and makes a random legal move.
//
// Two legacy bugs are fixed rather than kept (both are listed in the PR):
//   - its random pick indexed 1..length, so it never chose the first option
//     and sometimes chose past the end, which threw and froze the game;
//   - it could pick a unit with nowhere to go (a boxed-in trebuchet) and
//     silently pass. It now picks among units that have a legal action.

// Least to most valuable. The legacy search ran this list in order and let
// each later match overwrite the last, so the final entry wins.
export const KILL_PRIORITY = Object.freeze([
  "rabble", "lighthorse", "spearman", "crossbowman", "heavyhorse",
  "elephant", "trebuchet", "catapult", "dragon", "king"
]);

// The computer's next action as { from, to }, or null when it has none.
export function chooseAction(game, rng = Math.random) {
  const movers = game.selectableHexes().filter((hex) => game.pieceAt(hex).type.codename !== "mountain");

  const kill = bestKill(game, movers);
  if (kill) return kill;

  const able = movers.filter((hex) => {
    const { moves, attacks } = game.actionsFrom(hex);
    return moves.length + attacks.length > 0;
  });
  if (able.length === 0) return null;

  const from = pick(able, rng);
  const { moves, attacks } = game.actionsFrom(from);
  return { from, to: attacks.length > 0 ? pick(attacks, rng) : pick(moves, rng) };
}

// Among every capture the given units can make, the one on the most valuable
// target. Ties go to the last in board order, as the legacy overwrite did.
export function bestKill(game, fromHexes) {
  let best = null;
  let bestRank = -1;
  for (const from of fromHexes) {
    for (const to of game.actionsFrom(from).attacks) {
      const rank = KILL_PRIORITY.indexOf(game.pieceAt(to).type.codename);
      if (rank >= bestRank) {
        best = { from, to };
        bestRank = rank;
      }
    }
  }
  return best;
}

function pick(list, rng) {
  return list[Math.floor(rng() * list.length)];
}
