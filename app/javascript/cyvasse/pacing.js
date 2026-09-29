// The computer's rhythm on the board (task cyvasse-bot-move-pacing): it
// selects a piece, holds it so the player sees it, then moves; a cavalry
// unit's second jump waits again. Milliseconds, each drawn at random from its
// range. LiveMatch::BOT_PACING is the server's copy for live matches.
export const BOT_PACING = Object.freeze({
  select: Object.freeze([2000, 5000]),
  move: Object.freeze([3000, 5000]),
  second: Object.freeze([2000, 3000])
});

// One turn's delays. `pace` scales them all; 0 makes the turn instant (tests).
export function botDelays(rng = Math.random, pace = 1) {
  const draw = ([low, high]) => (low + rng() * (high - low)) * pace;
  return { select: draw(BOT_PACING.select), move: draw(BOT_PACING.move), second: draw(BOT_PACING.second) };
}
