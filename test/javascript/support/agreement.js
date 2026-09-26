// The golden record the Ruby rules port is held to.
//
// The server validates every online move with a Ruby mirror of this engine
// (app/models/cyvasse_rules). Two languages can drift, so this module asks
// the JavaScript engine itself for its answers on many seeded positions and
// whole seeded games, and writes them to test/fixtures/files/rules_agreement.json:
//
//   - test/javascript/agreement_fixture_test.js fails when the engine's
//     answers no longer equal the checked-in file (a JS rules change must
//     regenerate it: bin/rules-agreement);
//   - test/models/cyvasse_rules/js_agreement_test.rb fails when the Ruby port
//     disagrees with the file.
//
// Both lanes run on every PR, so a rule changed on one side only goes red.
import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { legalActions } from "cyvasse/rules";
import { ARMY, UNIT_TYPES } from "cyvasse/units";
import { HEXES, PLAYER_ZONE, COMPUTER_ZONE } from "cyvasse/board";
import { formatLineup } from "cyvasse/setups";
import { seeded } from "./fixtures.js";

export const SCATTER_POSITIONS = 60;
export const GAMES = 6;
export const MAX_TURNS = 150;

export function buildAgreementFixture() {
  return { positions: scatterPositions(), games: playedGames() };
}

// Armies of random size strewn anywhere on the board: every unit type in
// every neighbourhood, mountains in lines of fire, dragons over crowds.
function scatterPositions() {
  const rng = seeded(20140925);
  const out = [];
  for (let n = 0; n < SCATTER_POSITIONS; n++) {
    const hexes = shuffle(HEXES.map((h) => h.index), rng);
    const units = [];
    for (const team of [COMPUTER, PLAYER]) {
      const count = 4 + Math.floor(rng() * 16);
      const indices = shuffle(ARMY.map((_, i) => i + 1), rng).slice(0, count).sort((a, b) => a - b);
      for (const index of indices) units.push([team, index, hexes.pop()]);
    }
    const pieces = new Map(units.map(([team, index, hex]) => [hex, { team, type: UNIT_TYPES[ARMY[index - 1]] }]));
    const position = { pieceAt: (hex) => pieces.get(hex) };
    const actions = [];
    for (const [, index, hex] of units) {
      const jumps = UNIT_TYPES[ARMY[index - 1]].rank === "cavalry" ? [1, 2] : [1];
      for (const jump of jumps) {
        const { moves, attacks } = legalActions(position, hex, { jump });
        actions.push([hex, jump, moves, attacks]);
      }
    }
    out.push({ units, actions });
  }
  return out;
}

// Whole games between two random players, every turn recorded with the state
// it leaves: who moves, the turn count, the marks, captures, passes, the end.
function playedGames() {
  const games = [];
  for (let g = 0; g < GAMES; g++) {
    const rng = seeded(1000 + g);
    const homeHexes = shuffle([...PLAYER_ZONE], rng);
    const awayHexes = shuffle([...COMPUTER_ZONE], rng);
    const home = formatLineup(ARMY.map((_, i) => [i + 1, homeHexes[i]]));
    const away = formatLineup(ARMY.map((_, i) => [i + 1, awayHexes[i]]));
    const game = new Game({ rng, computer: { name: "fixture", lineup: away } });
    for (const pair of home.split("|").filter(Boolean)) {
      const [unit, hex] = pair.split(":").map(Number);
      game.place(`${PLAYER}-${unit}`, hex);
    }
    game.start();
    const record = { home, away, first: game.offense, turns: [] };

    while (game.phase === "play" && record.turns.length < MAX_TURNS) {
      const mover = game.offense;
      const steps = [];
      let result;
      do {
        const options = [];
        for (const from of game.selectableHexes()) {
          const { moves, attacks } = game.actionsFrom(from);
          for (const to of [...moves, ...attacks]) options.push([from, to]);
        }
        const [from, to] = options[Math.floor(rng() * options.length)];
        steps.push([from, to]);
        result = game.act(from, to);
      } while (result.secondJump);
      record.turns.push({
        mover,
        steps,
        dead: game.units.filter((u) => u.status === "dead").length,
        offense: game.offense,
        turn: game.turn,
        lastMove: game.lastMove,
        utilMove: game.utilMove,
        passed: result.passed,
        over: result.over,
        winner: game.winner
      });
    }
    games.push(record);
  }
  return games;
}

function shuffle(array, rng) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}

// One line per position and per game, so a diff of the file reads.
export function serialize(fixture) {
  const lines = (items) => items.map((item) => `    ${JSON.stringify(item)}`).join(",\n");
  return `{\n  "positions": [\n${lines(fixture.positions)}\n  ],\n  "games": [\n${lines(fixture.games)}\n  ]\n}\n`;
}
