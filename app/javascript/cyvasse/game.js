// One game of Cyvasse against the computer: setup, turns, captures, the win.
//
// Ported from amcritchie/Cyvasse app/assets/javascripts/{game,offense,
// pregame,randomLoadUnits,placeUnits}.js with the jQuery, the AJAX and the
// server round-trips taken out. A Game holds no DOM; the board controller
// (app/javascript/controllers/cyvasse_game_controller.js) draws it.
//
// Seats follow the legacy vs-computer match: the player is the home side,
// team 1, deploying on the bottom five rows; the computer is team 0 on top.

import { ARMY, typeAt } from "cyvasse/units";
import { hexAt, inPlayerZone, PLAYER_ZONE } from "cyvasse/board";
import { legalActions } from "cyvasse/rules";
import { formatLineup, parseLineup, pickComputerLineup } from "cyvasse/setups";

export const PLAYER = 1;
export const COMPUTER = 0;

export class Game {
  // rng: a () => [0, 1) source, injectable so tests are deterministic.
  // computer: { name, lineup } to pin the opponent; picked at random if absent.
  constructor({ rng = Math.random, computer } = {}) {
    this.rng = rng;
    this.computer = computer ?? pickComputerLineup(rng);
    this.units = [];
    for (const team of [COMPUTER, PLAYER]) {
      ARMY.forEach((_, i) => {
        const index = i + 1;
        this.units.push({ id: `${team}-${index}`, team, index, type: typeAt(index), status: "unplaced", hex: null });
      });
    }
    this.phase = "setup";
    this.turn = 0;
    this.offense = null;
    this.jump = 1;
    this.activeHex = null;
    this.lastMove = [];
    this.utilMove = null;
    this.winner = null;
  }

  // An online match as the server sends it (Match#state_for), from this
  // player's seat: their army is PLAYER (team 1) on the bottom rows, the
  // opponent's COMPUTER (team 0). `units` lists [team, armyIndex, hex, status];
  // a unit it leaves out stays in the dock (the opponent's army before the
  // game starts). The server, not this object, decides every outcome: a
  // restored game only draws the board and offers the legal moves.
  static restore({ phase, turn, offense, units = [], lastMove = [], utilMove = null, winner = null }) {
    const game = new Game({ computer: { name: "", lineup: "" } });
    for (const [team, index, hex, status] of units) {
      const unit = game.unit(`${team}-${index}`);
      unit.status = status;
      unit.hex = status === "alive" ? hex : null;
    }
    game.phase = phase;
    game.turn = turn ?? 0;
    game.offense = offense ?? null;
    game.lastMove = lastMove ?? [];
    game.utilMove = utilMove ?? null;
    game.winner = winner ?? null;
    return game;
  }

  // The player's own army as the legacy setup string, from their seat
  // ("unitIndex:hex|", hexes 52-91): what an online match submits.
  playerLineup() {
    return formatLineup(this.teamUnits(PLAYER).map((u) => [u.index, u.hex]));
  }

  // ---- The board ---------------------------------------------------------

  pieceAt(hexIndex) {
    return this.units.find((u) => u.status === "alive" && u.hex === hexIndex);
  }

  unit(id) {
    const found = this.units.find((u) => u.id === id);
    if (!found) throw new Error(`no unit ${id}`);
    return found;
  }

  teamUnits(team, status) {
    return this.units.filter((u) => u.team === team && (!status || u.status === status));
  }

  graveyard(team) {
    return this.teamUnits(team, "dead");
  }

  // ---- Setup (pregame.js, randomLoadUnits.js) ----------------------------

  // Put one of the player's units on an empty hex of their five rows. A
  // placed unit may be moved again until the game starts.
  place(unitId, hexIndex) {
    this.#requirePhase("setup");
    const unit = this.unit(unitId);
    if (unit.team !== PLAYER) throw new Error("only the player's own units are placed by hand");
    if (!inPlayerZone(hexIndex)) throw new Error(`hex ${hexIndex} is outside your deploy rows`);
    if (this.pieceAt(hexIndex)) throw new Error(`hex ${hexIndex} is occupied`);
    unit.status = "alive";
    unit.hex = hexIndex;
  }

  // The "Random Setup" button. With units still in the dock it scatters only
  // those onto free hexes; with every unit placed it reshuffles the lot.
  randomSetup() {
    this.#requirePhase("setup");
    const units = this.teamUnits(PLAYER);
    const unplaced = units.filter((u) => u.status === "unplaced");
    if (unplaced.length === 0) {
      const spots = shuffle([...PLAYER_ZONE], this.rng);
      units.forEach((u) => {
        u.status = "alive";
        u.hex = spots.pop();
      });
    } else {
      const free = shuffle(PLAYER_ZONE.filter((i) => !this.pieceAt(i)), this.rng);
      unplaced.forEach((u) => {
        u.status = "alive";
        u.hex = free.pop();
      });
    }
  }

  get readyToStart() {
    return this.phase === "setup" && this.teamUnits(PLAYER, "unplaced").length === 0;
  }

  // "Start Game": the computer's lineup takes the board and the side whose
  // king stands nearer the middle row moves first (Game.whoGoesFirst).
  start() {
    if (!this.readyToStart) throw new Error("place every unit before starting");
    for (const [index, hex] of parseLineup(this.computer.lineup)) {
      const unit = this.unit(`${COMPUTER}-${index}`);
      unit.status = "alive";
      unit.hex = hex;
    }
    this.phase = "play";
    this.turn = 1;
    this.offense = this.#whoGoesFirst();
    this.#beginTurn();
  }

  #whoGoesFirst() {
    const distance = (team) => Math.abs(6 - hexAt(this.#king(team).hex).y);
    const computer = distance(COMPUTER);
    const player = distance(PLAYER);
    if (computer > player) return PLAYER;
    if (computer < player) return COMPUTER;
    return Math.floor(this.rng() * 2);
  }

  #king(team) {
    return this.units.find((u) => u.team === team && u.type.codename === "king");
  }

  // ---- Turns (offense.js, game.js) ---------------------------------------

  // Hexes holding a unit the side to move may select. Mountains are
  // selectable, as they were; they simply have nowhere to go. During a
  // cavalry unit's second jump only that unit may act.
  selectableHexes() {
    if (this.phase !== "play") return [];
    if (this.activeHex !== null) return [this.activeHex];
    return this.teamUnits(this.offense, "alive").map((u) => u.hex).sort((a, b) => a - b);
  }

  actionsFrom(hexIndex) {
    return legalActions(this, hexIndex, { jump: this.jump });
  }

  // Move or capture from one hex to another (Offense.moveToAttack). Returns
  // what happened: { captured, secondJump, turnEnded, passed, over }.
  act(fromHex, toHex) {
    this.#requirePhase("play");
    if (!this.selectableHexes().includes(fromHex)) throw new Error(`hex ${fromHex} cannot act now`);
    const { moves, attacks } = this.actionsFrom(fromHex);
    if (!moves.includes(toHex) && !attacks.includes(toHex)) throw new Error(`${fromHex} -> ${toHex} is not a legal action`);

    const unit = this.pieceAt(fromHex);
    const target = this.pieceAt(toHex);
    if (this.jump === 1) this.utilMove = null;

    let captured = null;
    if (target) {
      target.status = "dead";
      target.hex = null;
      captured = target;
      // Shooters stay put; everyone else steps into the captured hex.
      if (unit.type.attackRange === 0) unit.hex = toHex;
    } else {
      unit.hex = toHex;
    }

    const kingFell = captured?.type.codename === "king";
    if (unit.type.rank === "cavalry" && this.jump === 1 && !kingFell) {
      this.utilMove = fromHex;
      this.jump = 2;
      this.activeHex = unit.hex;
      const next = this.actionsFrom(this.activeHex);
      if (next.moves.length + next.attacks.length > 0) {
        return { captured, secondJump: true, turnEnded: false, passed: false, over: false };
      }
    }

    this.lastMove = [fromHex, toHex];
    return { captured, secondJump: false, ...this.#finishTurn() };
  }

  #finishTurn() {
    if (this.#king(1 - this.offense).status === "dead") {
      this.phase = "over";
      this.winner = this.offense;
      return { turnEnded: true, passed: false, over: true };
    }
    this.turn += 1;
    this.offense = 1 - this.offense;
    return { turnEnded: true, ...this.#beginTurn() };
  }

  #beginTurn() {
    this.jump = 1;
    this.activeHex = null;
    if (this.#hasAnyAction(this.offense)) return { passed: false, over: false };

    // Nothing can move: the legacy game would sit waiting forever. The turn
    // passes instead; if neither side can move, the game ends drawn.
    this.offense = 1 - this.offense;
    this.turn += 1;
    if (this.#hasAnyAction(this.offense)) return { passed: true, over: false };
    this.phase = "over";
    this.winner = null;
    return { passed: true, over: true };
  }

  #hasAnyAction(team) {
    return this.teamUnits(team, "alive").some((u) => {
      const { moves, attacks } = this.actionsFrom(u.hex);
      return moves.length + attacks.length > 0;
    });
  }

  #requirePhase(phase) {
    if (this.phase !== phase) throw new Error(`not in the ${phase} phase (now ${this.phase})`);
  }
}

// Fisher-Yates with an injectable source; returns the array it shuffled.
export function shuffle(array, rng = Math.random) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}
