// [unit] Loading a saved lineup (piece 10b): the whole army takes the board
// from the player's seat, over anything placed by hand, and a lineup that is
// not a whole army on the player's rows leaves the board as it was.
import { test } from "node:test";
import assert from "node:assert/strict";

import { Game, PLAYER } from "cyvasse/game";
import { formatLineup } from "cyvasse/setups";
import { seeded } from "./support/fixtures.js";

const army = (hexes) => formatLineup(hexes.map((hex, i) => [i + 1, hex]));
const range = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => from + i);
const WALL = army(range(73, 91));

test("a saved lineup places every unit where it was saved and the game is ready to start", () => {
  const game = new Game({ rng: seeded(3) });
  game.loadLineup(WALL);
  assert.equal(game.teamUnits(PLAYER, "unplaced").length, 0);
  assert.ok(game.readyToStart);
  assert.equal(game.pieceAt(73).id, `${PLAYER}-1`);
  assert.equal(game.pieceAt(91).id, `${PLAYER}-19`);
  assert.equal(game.playerLineup(), WALL, "what an online match would submit");
});

test("loading replaces an army placed by hand, even on the hexes the lineup uses", () => {
  const game = new Game({ rng: seeded(4) });
  game.randomSetup();
  game.loadLineup(WALL);
  assert.equal(game.playerLineup(), WALL);
  assert.equal(game.teamUnits(PLAYER, "alive").length, 19);
});

test("a lineup that is not a whole army on the player's rows is refused and changes nothing", () => {
  const cases = {
    "missing a unit": army(range(52, 69)),
    "on the computer's rows": army(range(1, 19)),
    "two units on one hex": army([...range(52, 69), 52]),
    "empty": ""
  };
  for (const [label, lineup] of Object.entries(cases)) {
    const game = new Game({ rng: seeded(5) });
    game.place(`${PLAYER}-1`, 60);
    assert.throws(() => game.loadLineup(lineup), Error, label);
    assert.equal(game.unit(`${PLAYER}-1`).hex, 60, label);
    assert.equal(game.teamUnits(PLAYER, "unplaced").length, 18, label);
  }
});

test("a lineup loads only during setup", () => {
  const game = new Game({ rng: seeded(6) });
  game.loadLineup(WALL);
  game.start();
  assert.throws(() => game.loadLineup(WALL), /setup phase/);
});
