// [unit] Tyrion's brain (script/tyrion/brain.mjs): his five setups hold to
// the rules and keep their promises about the king, every turn he picks is
// one the engine allows, and his search beats the legacy greedy computer.
import { test } from "node:test";
import assert from "node:assert/strict";

import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { COMPUTER_ZONE } from "cyvasse/board";
import { OPENINGS, openingLineup } from "cyvasse/openings";
import { COMPUTER_OPPONENTS } from "cyvasse/setups";
import { legalActions } from "cyvasse/rules";
import { UNIT_TYPES } from "cyvasse/units";
import { SETUPS, chooseSetup, chooseTurn, legalTurns, gameFromState } from "../../script/tyrion/brain.mjs";
import { seeded } from "./support/fixtures.js";
import { playOne } from "./support/tyrion_selfplay.js";

const loaded = (rows) => {
  const game = new Game({ rng: seeded(1), computer: { name: "", lineup: "" } });
  game.loadLineup(openingLineup({ rows }));
  return game;
};
const kingHex = (game, team = PLAYER) => game.teamUnits(team).find((u) => u.type.codename === "king").hex;

// One enemy raider on any of their forty hexes, our whole army on the board,
// the enemy to move: can it take our king this turn (both cavalry jumps)?
function raids(rows) {
  const hits = [];
  for (const kind of ["dragon", "lighthorse", "heavyhorse", "elephant", "rabble"]) {
    for (const hex of COMPUTER_ZONE) {
      const game = loaded(rows);
      const raider = game.units.find((u) => u.team === COMPUTER && u.type.codename === kind);
      raider.status = "alive";
      raider.hex = hex;
      game.phase = "play";
      game.turn = 1;
      game.offense = COMPUTER;
      const king = kingHex(game);
      if (legalTurns(game).some((t) => t.steps.some(([, to]) => to === king))) hits.push(`${kind}@${hex}`);
    }
  }
  return hits;
}

test("five setups, each a whole army on his rows, none a panel opening", () => {
  assert.equal(Object.keys(SETUPS).length, 5);
  const panel = new Set(OPENINGS.map(openingLineup));
  for (const [slug, rows] of Object.entries(SETUPS)) {
    assert.deepEqual(rows.map((r) => r.length), [10, 9, 8, 7, 6], slug);
    assert.ok(loaded(rows).readyToStart, slug);
    assert.ok(!panel.has(openingLineup({ rows })), `${slug} repeats a panel opening`);
  }
});

test("no enemy dragon, horse, elephant or rabble can take his king on the first turn", () => {
  for (const [slug, rows] of Object.entries(SETUPS)) assert.deepEqual(raids(rows), [], slug);
});

test("the raid check bites: the panel's King's Gambit is raidable", () => {
  const gambit = OPENINGS.find((o) => o.slug === "kings-gambit");
  assert.ok(raids(gambit.rows).length > 0);
});

test("the Lannister Debt moves first against every computer army", () => {
  for (const { name, lineups } of COMPUTER_OPPONENTS) {
    for (const lineup of lineups) {
      const game = new Game({ rng: seeded(2), computer: { name, lineup } });
      game.loadLineup(openingLineup({ rows: SETUPS["lannister-debt"] }));
      game.start();
      assert.equal(game.offense, PLAYER, `${name}: ${lineup}`);
    }
  }
});

test("the Lannister Debt collects: a dragon that takes either crossbow is taken back", () => {
  const game = loaded(SETUPS["lannister-debt"]);
  const pieces = new Map(game.teamUnits(PLAYER).map((u) => [u.hex, { team: PLAYER, type: u.type }]));
  const crossbows = game.teamUnits(PLAYER).filter((u) => u.type.codename === "crossbowman").map((u) => u.hex);
  assert.equal(crossbows.length, 2);
  for (const x of crossbows) {
    const position = { pieceAt: (i) => (i === x ? { team: COMPUTER, type: UNIT_TYPES.dragon } : pieces.get(i)) };
    const takers = [...pieces.keys()].filter((h) => h !== x && legalActions(position, h).attacks.includes(x));
    assert.ok(takers.length >= 2, `a dragon on ${x} is answered by ${takers.length}`);
  }
});

test("chooseSetup picks each of the five, by weight", () => {
  const rng = seeded(7);
  const seen = new Map();
  for (let i = 0; i < 200; i++) {
    const { slug, lineup } = chooseSetup(rng);
    assert.equal(lineup, openingLineup({ rows: SETUPS[slug] }));
    seen.set(slug, (seen.get(slug) ?? 0) + 1);
  }
  assert.deepEqual([...seen.keys()].sort(), Object.keys(SETUPS).sort());
  assert.ok(seen.get("lannister-debt") > seen.get("small-folk"), "the Debt is his favourite");
});

test("legalTurns makes cavalry take its second jump, as the server requires", () => {
  const game = loaded(SETUPS["small-folk"]);
  game.phase = "play";
  game.turn = 1;
  game.offense = PLAYER;
  const turns = legalTurns(game);
  const horse = game.teamUnits(PLAYER).find((u) => u.type.codename === "lighthorse").hex;
  const fromHorse = turns.filter((t) => t.steps[0][0] === horse);
  assert.ok(fromHorse.length > 0);
  assert.ok(fromHorse.every((t) => t.steps.length === 2 && t.steps[1][0] === t.steps[0][1]));
});

test("every turn he chooses is legal, and he takes a king left open", () => {
  const game = new Game({ rng: seeded(5), computer: { name: COMPUTER_OPPONENTS[0].name, lineup: COMPUTER_OPPONENTS[0].lineups[0] } });
  game.loadLineup(openingLineup({ rows: SETUPS["the-drains"] }));
  game.start();
  // Strip the enemy to its king on a hex his crossbow reaches.
  for (const unit of game.teamUnits(COMPUTER)) if (unit.type.codename !== "king") { unit.status = "dead"; unit.hex = null; }
  const crossbow = game.teamUnits(PLAYER).find((u) => u.type.codename === "crossbowman");
  const target = legalActions(game, crossbow.hex).moves[0];
  game.unit(`${COMPUTER}-17`).hex = target;
  game.offense = PLAYER;
  const steps = chooseTurn(game, seeded(1));
  for (const [from, to] of steps) game.act(from, to);
  assert.equal(game.phase, "over");
  assert.equal(game.winner, PLAYER);
});

test("gameFromState reads the server's state from his seat", () => {
  const lineup = openingLineup({ rows: SETUPS["blackwater"] });
  const units = lineup.split("|").filter(Boolean).map((p) => p.split(":").map(Number)).map(([i, h]) => [1, i, h, "alive"]);
  const game = gameFromState({ phase: "play", turn: 1, offense: 1, units, last_move: [], util_move: null, winner: null });
  assert.equal(game.offense, PLAYER);
  assert.ok(chooseTurn(game, seeded(1)).length >= 1);
});

// About ten seconds a game; three seeded games keep the lane quick.
test("his search beats the legacy greedy computer", () => {
  const results = [11, 12, 13].map((seed) => playOne(seed));
  assert.ok(results.filter((r) => r === "win").length >= 2, results.join(", "));
});
