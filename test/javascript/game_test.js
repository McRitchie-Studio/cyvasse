// [unit] Setup, turn order, the cavalry double jump, the win, and the
// computer opponent, played out end to end.
import { test } from "node:test";
import assert from "node:assert/strict";

import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { chooseAction, bestKill, KILL_PRIORITY } from "cyvasse/ai";
import { COMPUTER_OPPONENTS, parseLineup, formatLineup, pickComputerLineup } from "cyvasse/setups";
import { ARMY_SIZE } from "cyvasse/units";
import { hexAt, mirror, PLAYER_ZONE } from "cyvasse/board";
import { seeded } from "./support/fixtures.js";

const FIRST_LINEUP = { name: "Qavo Nogarys", lineup: COMPUTER_OPPONENTS[0].lineups[0] };

// A game with the player's army placed as the mirror image of a legacy
// computer lineup, so both sides start from a real legacy setup.
function readyGame({ rng = seeded(1), computer = FIRST_LINEUP, player = COMPUTER_OPPONENTS[1].lineups[0] } = {}) {
  const game = new Game({ rng, computer });
  for (const [index, hex] of parseLineup(player)) game.place(`${PLAYER}-${index}`, mirror(hex));
  return game;
}

// Clear the board and stand units where a test wants them.
function arrange(game, spots) {
  for (const unit of game.units) {
    unit.status = "dead";
    unit.hex = null;
  }
  for (const [id, hex] of Object.entries(spots)) {
    const unit = game.unit(id);
    unit.status = "alive";
    unit.hex = hex;
  }
}

test("every legacy lineup is a full army on distinct hexes of the computer's rows", () => {
  assert.equal(COMPUTER_OPPONENTS.length, 6);
  for (const { name, lineups } of COMPUTER_OPPONENTS) {
    assert.equal(lineups.length, 3, name);
    for (const lineup of lineups) {
      const pairs = parseLineup(lineup);
      assert.equal(pairs.length, ARMY_SIZE);
      assert.deepEqual(pairs.map(([u]) => u).sort((a, b) => a - b), Array.from({ length: 19 }, (_, i) => i + 1));
      assert.equal(new Set(pairs.map(([, h]) => h)).size, ARMY_SIZE);
      assert.ok(pairs.every(([, h]) => h >= 1 && h <= 40), `${name}: ${lineup}`);
      assert.equal(formatLineup(pairs), lineup, "the format round-trips");
    }
  }
});

test("the computer's lineup is drawn from the legacy table", () => {
  const { name, lineup } = pickComputerLineup(seeded(9));
  const opponent = COMPUTER_OPPONENTS.find((o) => o.name === name);
  assert.ok(opponent.lineups.includes(lineup));
});

test("a new game starts in setup with both armies in the dock", () => {
  const game = new Game({ rng: seeded(2) });
  assert.equal(game.phase, "setup");
  assert.equal(game.teamUnits(PLAYER, "unplaced").length, 19);
  assert.equal(game.teamUnits(COMPUTER, "unplaced").length, 19);
  assert.equal(game.readyToStart, false);
});

test("the player places units only on empty hexes of their own five rows", () => {
  const game = new Game({ rng: seeded(3) });
  game.place("1-17", 86);
  assert.equal(game.pieceAt(86).type.codename, "king");
  assert.throws(() => game.place("1-1", 86), /occupied/);
  assert.throws(() => game.place("1-1", 46), /outside your deploy rows/);
  assert.throws(() => game.place("0-1", 60), /player's own units/);
  game.place("1-17", 60);
  assert.equal(game.pieceAt(86), undefined, "a placed unit can be moved again");
});

test("random setup fills the dock, then reshuffles a full board", () => {
  const game = new Game({ rng: seeded(4) });
  game.place("1-17", 91);
  game.randomSetup();
  assert.equal(game.pieceAt(91).type.codename, "king", "units already placed stay put");
  assert.ok(game.readyToStart);
  const before = game.teamUnits(PLAYER).map((u) => u.hex).join();
  game.randomSetup();
  const hexes = game.teamUnits(PLAYER).map((u) => u.hex);
  assert.notEqual(hexes.join(), before);
  assert.equal(new Set(hexes).size, 19);
  assert.ok(hexes.every((h) => PLAYER_ZONE.includes(h)));
});

test("start places the computer's legacy lineup and begins turn 1", () => {
  const game = readyGame();
  assert.throws(() => new Game().start(), /place every unit/);
  game.start();
  assert.equal(game.phase, "play");
  assert.equal(game.turn, 1);
  for (const [index, hex] of parseLineup(FIRST_LINEUP.lineup)) {
    assert.equal(game.pieceAt(hex).id, `${COMPUTER}-${index}`);
  }
});

test("the side whose king stands nearer the middle row moves first", () => {
  const placeKing = (hex) => {
    const game = new Game({ rng: seeded(5), computer: FIRST_LINEUP }); // computer king on hex 18, row 3
    game.randomSetup();
    const king = game.unit("1-17");
    const other = game.pieceAt(hex);
    if (other && other !== king) other.hex = king.hex;
    king.hex = hex;
    game.start();
    return game.offense;
  };
  assert.equal(hexAt(18).y, 3);
  assert.equal(placeKing(58), PLAYER, "row 7 is nearer the middle than row 3");
  assert.equal(placeKing(88), COMPUTER, "row 11 is further");
  const tie = [1, 2, 3, 4].map((s) => {
    const game = new Game({ rng: seeded(s), computer: FIRST_LINEUP });
    game.randomSetup();
    const king = game.unit("1-17");
    const other = game.pieceAt(76);
    if (other && other !== king) other.hex = king.hex;
    king.hex = 76; // row 9: three from the middle, like row 3
    game.start();
    return game.offense;
  });
  assert.ok(tie.includes(PLAYER) && tie.includes(COMPUTER), "a tie is a coin toss");
});

test("a move passes the turn and records the last move", () => {
  const game = readyGame();
  game.start();
  const mover = game.offense;
  const from = game.selectableHexes().find((h) => {
    const unit = game.pieceAt(h);
    return unit.type.rank !== "cavalry" && game.actionsFrom(h).moves.length > 0;
  });
  const to = game.actionsFrom(from).moves[0];
  const result = game.act(from, to);
  assert.equal(result.turnEnded, true);
  assert.equal(game.offense, 1 - mover);
  assert.equal(game.turn, 2);
  assert.deepEqual(game.lastMove, [from, to]);
  assert.throws(() => game.act(to, from), /cannot act now/, "the other side moves now");
});

test("an illegal target is refused", () => {
  const game = readyGame();
  game.start();
  const from = game.selectableHexes()[0];
  assert.throws(() => game.act(from, from), /not a legal action/);
});

test("cavalry jumps twice with the same unit in one turn", () => {
  const game = readyGame();
  game.start();
  arrange(game, { "1-8": 46, "1-17": 91, "0-17": 1, "0-1": 5 });
  game.offense = PLAYER;
  const first = game.act(46, 49);
  assert.equal(first.secondJump, true);
  assert.equal(game.offense, PLAYER);
  assert.deepEqual(game.selectableHexes(), [49], "only the horse may finish the turn");
  assert.throws(() => game.act(91, 85), /cannot act now/);
  const reach = game.actionsFrom(49).moves;
  assert.ok(reach.includes(51) && !reach.includes(46), "the second jump reaches two hexes, not three");
  const second = game.act(49, 51);
  assert.equal(second.turnEnded, true);
  assert.equal(game.offense, COMPUTER);
  assert.equal(game.utilMove, 46, "the first jump's start stays marked");
  assert.deepEqual(game.lastMove, [49, 51]);
});

test("a shooter captures from where it stands", () => {
  const game = readyGame();
  game.start();
  arrange(game, { "1-12": 46, "0-1": 48, "1-17": 91, "0-17": 1 });
  game.offense = PLAYER;
  const result = game.act(46, 48);
  assert.equal(result.captured.id, "0-1");
  assert.equal(game.unit("1-12").hex, 46);
  assert.deepEqual(game.graveyard(COMPUTER).map((u) => u.id).includes("0-1"), true);
});

test("capturing the king wins the game at once", () => {
  const game = readyGame();
  game.start();
  arrange(game, { "1-9": 46, "0-17": 47, "1-17": 91 });
  game.offense = PLAYER;
  game.turn = 7;
  const result = game.act(46, 47);
  assert.equal(result.over, true);
  assert.equal(result.secondJump, false, "a horse that takes the king does not jump again");
  assert.equal(game.phase, "over");
  assert.equal(game.winner, PLAYER);
  assert.equal(game.turn, 7, "the banner reads the turn the king fell");
  assert.deepEqual(game.selectableHexes(), []);
});

test("a side with nothing to move passes its turn", () => {
  const game = readyGame();
  game.start();
  // The computer's king in the corner, walled in by its own mountains and a
  // trebuchet, with no target in the trebuchet's reach: nothing can move.
  arrange(game, { "0-17": 1, "0-18": 2, "0-19": 7, "0-14": 8, "1-1": 60, "1-17": 91 });
  game.offense = PLAYER;
  game.turn = 4;
  const result = game.act(60, 61);
  assert.equal(result.passed, true);
  assert.equal(result.over, false);
  assert.equal(game.offense, PLAYER, "the computer's turn passed back");
  assert.equal(game.turn, 6);
});

test("the computer takes the most valuable piece it can reach", () => {
  const game = readyGame();
  game.start();
  arrange(game, { "0-6": 46, "0-8": 20, "1-1": 47, "1-17": 57, "1-16": 91, "0-17": 1 });
  game.offense = COMPUTER;
  assert.deepEqual(bestKill(game, game.selectableHexes()), { from: 46, to: 57 }, "the king over the rabble");
  assert.deepEqual(chooseAction(game, seeded(1)), { from: 46, to: 57 });
  assert.deepEqual(KILL_PRIORITY.at(-1), "king");
});

test("with nothing to take, the computer makes a random legal move", () => {
  const game = readyGame();
  game.start();
  game.offense = COMPUTER;
  for (let seed = 1; seed <= 20; seed++) {
    const { from, to } = chooseAction(game, seeded(seed));
    assert.notEqual(game.pieceAt(from).type.codename, "mountain");
    const { moves, attacks } = game.actionsFrom(from);
    assert.ok(moves.includes(to) || attacks.includes(to));
  }
});

test("computer against computer, every game runs to a king's capture", () => {
  for (let seed = 1; seed <= 12; seed++) {
    const rng = seeded(seed);
    const game = new Game({ rng });
    game.randomSetup();
    game.start();
    let plies = 0;
    while (game.phase === "play") {
      const action = chooseAction(game, rng);
      assert.ok(action, `seed ${seed}: the side to move always has an action`);
      game.act(action.from, action.to);
      plies += 1;
      assert.ok(plies < 5000, `seed ${seed}: the game should end`);
    }
    assert.equal(game.phase, "over");
    assert.notEqual(game.winner, null, `seed ${seed}: someone wins`);
    const loser = game.units.find((u) => u.team === 1 - game.winner && u.type.codename === "king");
    assert.equal(loser.status, "dead");
  }
});
