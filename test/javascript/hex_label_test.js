// [unit] What a screen reader hears for each hex (cyvasse/hex_label): the
// occupant, and while a unit of the player's is picked, what a click there
// would do; and the status line's word on the picked unit.
import { test } from "node:test";
import assert from "node:assert/strict";

import { hexLabel, hexStates, selectionNote, occupantName } from "cyvasse/hex_label";
import { UNIT_TYPES } from "cyvasse/units";
import { PLAYER, COMPUTER } from "cyvasse/game";

const piece = (codename, team) => ({ type: UNIT_TYPES[codename], team });
const dragon = piece("dragon", PLAYER);
const catapult = piece("catapult", COMPUTER);
const rabble = piece("rabble", PLAYER);
const mountain = piece("mountain", PLAYER);

test("a hex is named by its occupant, or by its index when empty", () => {
  assert.equal(hexLabel(42, null), "Hex 42");
  assert.equal(hexLabel(70, dragon), "Your dragon");
  assert.equal(hexLabel(30, catapult), "Enemy catapult");
  assert.equal(hexLabel(55, mountain), "Mountain");
  assert.equal(occupantName(piece("mountain", COMPUTER)), "Mountain", "a mountain is terrain, whoever set it");
  assert.equal(hexLabel(80, piece("lighthorse", PLAYER)), "Your light horse");
});

test("a picked unit's targets say what a click does", () => {
  assert.equal(hexLabel(70, dragon, "selected"), "Your dragon, selected");
  assert.equal(hexLabel(42, null, "move"), "Hex 42, move here");
  assert.equal(hexLabel(30, catapult, "attack"), "Attack enemy catapult");
  assert.equal(hexLabel(12, null, "unreachable"), "Hex 12, unreachable");
  assert.equal(hexLabel(30, catapult, "unreachable"), "Enemy catapult, unreachable");
  assert.equal(hexLabel(60, null, "place"), "Hex 60, place here");
});

test("play: states for every hex while the player's unit is picked", () => {
  const board = new Map([[70, dragon], [30, catapult], [72, rabble], [55, mountain]]);
  const states = hexStates({
    hexes: [12, 30, 42, 55, 59, 70, 72],
    pieceAt: (i) => board.get(i) ?? null,
    selectedHex: 70,
    actions: { moves: [42, 59], attacks: [30] }
  });
  assert.equal(states.get(70), "selected");
  assert.equal(states.get(42), "move");
  assert.equal(states.get(59), "move");
  assert.equal(states.get(30), "attack");
  assert.equal(states.get(12), "unreachable");
  assert.equal(states.get(55), "unreachable", "a mountain is never a place to go");
  assert.equal(states.has(72), false, "another unit of yours stays as it is: a click there picks it");
});

test("play: nothing picked, or the opponent's pick, leaves every hex plain", () => {
  const board = new Map([[70, dragon], [30, catapult]]);
  const pieceAt = (i) => board.get(i) ?? null;
  assert.equal(hexStates({ hexes: [30, 42, 70], pieceAt }).size, 0);
  const theirs = hexStates({ hexes: [30, 42, 70], pieceAt, selectedHex: 30, actions: { moves: [42], attacks: [70] } });
  assert.equal(theirs.size, 0, "the computer's pick is not the player's to act on");
});

test("setup: a picked unit's drop hexes say place here, and a placed pick is selected", () => {
  const fromDock = hexStates({ dropHexes: [60, 61], selectedHex: null });
  assert.deepEqual([...fromDock], [[60, "place"], [61, "place"]]);
  const placed = hexStates({ dropHexes: [60], selectedHex: 70 });
  assert.equal(placed.get(70), "selected");
});

test("the status line names the pick and counts its options", () => {
  assert.equal(selectionNote(dragon, { moves: [1, 2, 3, 4], attacks: [5] }), "Dragon selected: 4 moves, 1 attack.");
  assert.equal(selectionNote(rabble, { moves: [1], attacks: [] }), "Rabble selected: 1 move.");
  assert.equal(selectionNote(rabble, { moves: [], attacks: [2, 3] }), "Rabble selected: 2 attacks.");
  assert.equal(selectionNote(rabble, { moves: [], attacks: [] }), "Rabble selected: no legal moves.");
  assert.equal(selectionNote(null, { moves: [], attacks: [] }), "");
});
