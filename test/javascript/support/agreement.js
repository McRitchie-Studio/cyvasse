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
//
// Random games almost never reach a pass or a draw (the port's stalemate
// rule), so the record also holds a few set positions, SCENARIOS, played out
// from a given turn: a side with nothing to move passes, and a move that
// leaves neither side a move draws the game.
import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { mirror } from "cyvasse/board";
import { legalActions } from "cyvasse/rules";
import { ARMY, UNIT_TYPES } from "cyvasse/units";
import { HEXES, PLAYER_ZONE, COMPUTER_ZONE } from "cyvasse/board";
import { formatLineup } from "cyvasse/setups";
import { seeded } from "./fixtures.js";

export const SCATTER_POSITIONS = 60;
export const GAMES = 6;
export const MAX_TURNS = 150;

export function buildAgreementFixture() {
  return { positions: scatterPositions(), games: playedGames(), scenarios: playedScenarios() };
}

// A king in the corner behind its own two mountains and its trebuchet, the
// rest of the army captured: none of the four can act (the Ruby port's
// rules_test.rb "boxed" position). Army index => hex, from the home frame.
const BOXED_AWAY = { 14: 8, 17: 1, 18: 2, 19: 7 };
const BOXED_HOME = Object.fromEntries(Object.entries(BOXED_AWAY).map(([index, hex]) => [index, mirror(hex)]));

// Set positions played from `offense` at `turn`, each turn taking the first
// action on offer, for `turns` turns or until the game ends.
//   pass-*  one side is boxed in: every one of its turns passes back.
//   draw-*  a trebuchet takes the last enemy unit that could move; then
//           neither side can move and the game is drawn.
export const SCENARIOS = [
  { name: "pass-away", home: { 17: 80 }, away: BOXED_AWAY, offense: PLAYER, turn: 3, turns: 3 },
  { name: "pass-home", home: BOXED_HOME, away: { 17: 12 }, offense: COMPUTER, turn: 4, turns: 3 },
  { name: "draw-home-moves", home: BOXED_HOME, away: { ...BOXED_AWAY, 1: 66 }, offense: PLAYER, turn: 5, turns: 1 },
  { name: "draw-away-moves", home: { ...BOXED_HOME, 1: mirror(66) }, away: BOXED_AWAY, offense: COMPUTER, turn: 6, turns: 1 }
];

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
      record.turns.push(playTurn(game, (options) => options[Math.floor(rng() * options.length)]));
    }
    games.push(record);
  }
  return games;
}

// Each scenario from its set position. `home` and `away` are the legacy
// position strings the Ruby port starts from (CyvasseRules::Game.new).
function playedScenarios() {
  return SCENARIOS.map(({ name, home, away, offense, turn, turns }) => {
    const units = [];
    for (const [team, spots] of [[PLAYER, home], [COMPUTER, away]]) {
      ARMY.forEach((_, i) => {
        const hex = spots[i + 1];
        units.push([team, i + 1, hex ?? null, hex ? "alive" : "dead"]);
      });
    }
    const game = Game.restore({ phase: "play", turn, offense, units });
    const record = { name, home: positionString(PLAYER, home), away: positionString(COMPUTER, away), offense, turn, turns: [] };
    while (game.phase === "play" && record.turns.length < turns) {
      record.turns.push(playTurn(game, (options) => options[0]));
    }
    return record;
  });
}

// The legacy position string: "index:hex|" for a standing unit, "index:g<team>|"
// for a captured one, every army index in order.
function positionString(team, spots) {
  return ARMY.map((_, i) => `${i + 1}:${spots[i + 1] ?? `g${team}`}|`).join("");
}

// One whole turn (both jumps of a cavalry unit), the action at each step
// chosen by `pick` from every legal [from, to]; recorded with the state it
// leaves: who moves, the turn count, the marks, captures, passes, the end.
function playTurn(game, pick) {
  const mover = game.offense;
  const steps = [];
  let result;
  do {
    const options = [];
    for (const from of game.selectableHexes()) {
      const { moves, attacks } = game.actionsFrom(from);
      for (const to of [...moves, ...attacks]) options.push([from, to]);
    }
    const [from, to] = pick(options);
    steps.push([from, to]);
    result = game.act(from, to);
  } while (result.secondJump);
  return {
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
  };
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
  return `{\n  "positions": [\n${lines(fixture.positions)}\n  ],\n  "games": [\n${lines(fixture.games)}\n  ],\n  "scenarios": [\n${lines(fixture.scenarios)}\n  ]\n}\n`;
}
