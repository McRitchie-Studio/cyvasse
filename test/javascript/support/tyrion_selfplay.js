// Tyrion (script/tyrion/brain.mjs) against the legacy greedy computer
// (cyvasse/ai), each side choosing on the same engine.
import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { chooseAction } from "cyvasse/ai";
import { COMPUTER_OPPONENTS } from "cyvasse/setups";
import { chooseTurn, chooseSetup } from "../../../script/tyrion/brain.mjs";
import { seeded } from "./fixtures.js";

// One game, Tyrion as PLAYER. Returns "win", "loss" or "draw" (a draw also
// when the turn cap is reached).
export function playOne(seed, { maxTurns = 300 } = {}) {
  const rng = seeded(seed);
  const opponents = COMPUTER_OPPONENTS.flatMap(({ name, lineups }) => lineups.map((lineup) => ({ name, lineup })));
  const game = new Game({ rng, computer: opponents[seed % opponents.length] });
  game.loadLineup(chooseSetup(rng).lineup);
  game.start();
  while (game.phase === "play" && game.turn < maxTurns) {
    if (game.offense === PLAYER) {
      const steps = chooseTurn(game, rng);
      for (const [from, to] of steps) game.act(from, to);
    } else {
      let result;
      do {
        const action = chooseAction(game, rng);
        result = game.act(action.from, action.to);
      } while (result.secondJump);
    }
  }
  if (game.phase !== "over" || game.winner === null) return "draw";
  return game.winner === PLAYER ? "win" : "loss";
}

export { COMPUTER };
