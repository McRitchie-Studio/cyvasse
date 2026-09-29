// Tyrion's game: his five setups and how he picks a turn (task tyrion-runner).
//
// The character and the reasoning behind every number here are in the hub,
// mcritchie-studio docs/agents/agents/tyrion/game.md. The rules are the
// engine's own (app/javascript/cyvasse), imported unchanged, so every turn
// this module chooses is one the server's Match#play! accepts.
//
// A turn is chosen by a shallow search: every legal turn (both jumps for
// cavalry) is played out, scored by material and his temperament, and then
// charged for the opponent's best capture in reply. That sees a king left
// open to their dragon without a special term for it.

import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { openingLineup } from "cyvasse/openings";
import { hexAt } from "cyvasse/board";

// His five, in the openings panel's drawing (front row 7 to back row 11).
// Each is checked in test/javascript/tyrion_brain_test.js.
export const SETUPS = Object.freeze({
  "the-drains": ["L.SE..ES.L", "H..R.D..H", "M.X..T.M", "R....CX", ".R...K"],
  "lannister-debt": ["L.E.X..E.L", "H.STD..SH", "M.XKRC.M", "R.....R", "......"],
  "too-far-forward": ["L.R..R...L", ".E.CTX.E.", "H..RX..H", "M.SKS.M", "..D..."],
  "small-folk": ["S..E..E..S", ".X.L.L.X.", "R.HTCH.R", ".M.KD.M", "..R..."],
  "blackwater": ["L.SE.EM...", "H.R.S..X.", "R.XC.T.H", "M.K..DL", "..R..."]
});

// The Lannister Debt is his favourite and his gamble; it comes up most.
const SETUP_WEIGHTS = { "the-drains": 2, "lannister-debt": 3, "too-far-forward": 2, "small-folk": 1, "blackwater": 2 };

export function chooseSetup(rng = Math.random) {
  const entries = Object.entries(SETUP_WEIGHTS);
  let roll = rng() * entries.reduce((sum, [, w]) => sum + w, 0);
  for (const [slug, weight] of entries) {
    roll -= weight;
    if (roll < 0) return { slug, lineup: openingLineup({ rows: SETUPS[slug] }) };
  }
  const [slug] = entries.at(-1);
  return { slug, lineup: openingLineup({ rows: SETUPS[slug] }) };
}

// game.md "The numbers, for the runtime".
export const VALUES = Object.freeze({
  rabble: 1, lighthorse: 2, spearman: 2, crossbowman: 3, heavyhorse: 3,
  elephant: 4, trebuchet: 4, catapult: 5, dragon: 8, king: 1000, mountain: 0
});
const DRAGON_ABROAD = 2; // maxim 2: a dragon beyond his front row with nothing to take

// Every legal turn for the side to move, as { steps, snapshot }: the steps to
// post and the position after them. A cavalry unit's second jump is part of
// its turn whenever it has one, as the server requires.
export function legalTurns(game) {
  const turns = [];
  for (const from of game.selectableHexes()) {
    const { moves, attacks } = game.actionsFrom(from);
    for (const to of [...attacks, ...moves]) {
      const before = game.snapshot();
      const result = game.act(from, to);
      if (result.secondJump) {
        const hex = game.activeHex;
        const second = game.actionsFrom(hex);
        for (const to2 of [...second.attacks, ...second.moves]) {
          const mid = game.snapshot();
          game.act(hex, to2);
          turns.push({ steps: [[from, to], [hex, to2]], snapshot: game.snapshot() });
          game.restoreSnapshot(mid);
        }
      } else {
        turns.push({ steps: [[from, to]], snapshot: game.snapshot() });
      }
      game.restoreSnapshot(before);
    }
  }
  return turns;
}

// The position from `team`'s side: positive is good for it.
export function evaluate(game, team) {
  if (game.phase === "over") {
    if (game.winner === team) return 10_000;
    if (game.winner === null) return 0;
    return -10_000;
  }
  let score = 0;
  for (const unit of game.units) {
    if (unit.status !== "alive") continue;
    const sign = unit.team === team ? 1 : -1;
    score += sign * VALUES[unit.type.codename];
    if (unit.type.codename === "dragon" && dragonAbroad(game, unit)) score -= sign * DRAGON_ABROAD;
  }
  return score;
}

// Beyond its own front row (rows 1-5 for COMPUTER, 7-11 for PLAYER, in the
// seat the game is seen from) with no capture in reach.
function dragonAbroad(game, dragon) {
  const row = hexAt(dragon.hex).y;
  const home = dragon.team === PLAYER ? row >= 7 : row <= 5;
  if (home) return false;
  const saved = game.offense;
  game.offense = dragon.team;
  const { attacks } = game.actionsFrom(dragon.hex);
  game.offense = saved;
  return attacks.length === 0;
}

// The position after the opponent's best capture in reply, from `team`'s
// side (the position as it stands when they have none).
function worstReply(game, team) {
  if (game.phase !== "play" || game.offense === team) return evaluate(game, team);
  let worst = evaluate(game, team);
  for (const from of game.selectableHexes()) {
    const { attacks } = game.actionsFrom(from);
    for (const to of attacks) {
      const before = game.snapshot();
      const result = game.act(from, to);
      if (result.secondJump) {
        // Take the first jump's capture and the best second step.
        const hex = game.activeHex;
        const second = game.actionsFrom(hex);
        for (const to2 of [...second.attacks, ...second.moves]) {
          const mid = game.snapshot();
          game.act(hex, to2);
          worst = Math.min(worst, evaluate(game, team));
          game.restoreSnapshot(mid);
        }
      } else {
        worst = Math.min(worst, evaluate(game, team));
      }
      game.restoreSnapshot(before);
    }
  }
  return worst;
}

// His turn in `game` (the side to move), or null if it has none.
export function chooseTurn(game, rng = Math.random) {
  const team = game.offense;
  const candidates = legalTurns(game);
  if (candidates.length === 0) return null;
  const start = game.snapshot();
  let best = null;
  let bestScore = -Infinity;
  for (const turn of candidates) {
    game.restoreSnapshot(turn.snapshot);
    // A tiny random tiebreak, so equal turns do not always resolve the same way.
    const score = worstReply(game, team) + rng() * 0.01;
    if (score > bestScore) {
      best = turn;
      bestScore = score;
    }
  }
  game.restoreSnapshot(start);
  return best.steps;
}

// A game as the server sends it (Match#state_for), from his own seat.
export function gameFromState(state) {
  return Game.restore({
    phase: state.phase, turn: state.turn, offense: state.offense, units: state.units,
    lastMove: state.last_move, utilMove: state.util_move, winner: state.winner
  });
}

export { PLAYER, COMPUTER };
