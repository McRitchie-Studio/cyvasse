// [component] What a board click does to the picked piece (cyvasse/selection),
// the decision the /play and /matches board controllers act on.
import { test } from "node:test";
import assert from "node:assert/strict";

import { playIntent, setupIntent } from "cyvasse/selection";
import { Game, PLAYER, COMPUTER } from "cyvasse/game";

const picked = { selectedHex: 70, actions: { moves: [59, 60], attacks: [48] }, selectable: [70, 72, 81] };

test("play: a legal move or attack acts", () => {
  assert.equal(playIntent({ ...picked, hex: 60 }), "act");
  assert.equal(playIntent({ ...picked, hex: 48 }), "act");
});

test("play: another own piece switches the selection", () => {
  assert.equal(playIntent({ ...picked, hex: 72 }), "select");
});

test("play: the picked piece again deselects", () => {
  assert.equal(playIntent({ ...picked, hex: 70 }), "deselect");
});

test("play: a click off the board deselects", () => {
  assert.equal(playIntent({ ...picked, hex: null }), "deselect");
});

test("play: an unreachable hex deselects", () => {
  assert.equal(playIntent({ ...picked, hex: 5 }), "deselect");
  assert.equal(playIntent({ ...picked, hex: 90 }), "deselect");
});

test("play: with nothing picked, own pieces select and the rest do nothing", () => {
  const idle = { selectedHex: null, actions: null, selectable: [70, 72] };
  assert.equal(playIntent({ ...idle, hex: 70 }), "select");
  assert.equal(playIntent({ ...idle, hex: 5 }), "none");
  assert.equal(playIntent({ ...idle, hex: null }), "none");
});

test("play: on a real opening position every non-target hex deselects", () => {
  const game = new Game();
  game.randomSetup();
  game.start();
  const from = game.selectableHexes()[0];
  const actions = game.actionsFrom(from);
  const selectable = game.selectableHexes();
  for (let hex = 1; hex <= 91; hex++) {
    const intent = playIntent({ hex, selectedHex: from, actions, selectable });
    if (actions.moves.includes(hex) || actions.attacks.includes(hex)) assert.equal(intent, "act", `hex ${hex}`);
    else if (hex !== from && selectable.includes(hex)) assert.equal(intent, "select", `hex ${hex}`);
    else assert.equal(intent, "deselect", `hex ${hex}`);
  }
});

const mine = { id: "p1", team: PLAYER };

test("setup: the picked unit again deselects; another own unit switches", () => {
  assert.equal(setupIntent({ hex: 60, unit: mine, selectedUnitId: "p1" }), "deselect");
  assert.equal(setupIntent({ hex: 60, unit: mine, selectedUnitId: "p2" }), "select");
  assert.equal(setupIntent({ hex: 60, unit: mine, selectedUnitId: null }), "select");
});

test("setup: an empty hex in the deploy rows places the picked unit", () => {
  assert.equal(setupIntent({ hex: 60, unit: null, selectedUnitId: "p1" }), "place");
});

test("setup: off the board, outside the deploy rows, or an enemy deselects", () => {
  assert.equal(setupIntent({ hex: null, unit: null, selectedUnitId: "p1" }), "deselect");
  assert.equal(setupIntent({ hex: 10, unit: null, selectedUnitId: "p1" }), "deselect");
  assert.equal(setupIntent({ hex: 10, unit: { id: "c1", team: COMPUTER }, selectedUnitId: "p1" }), "deselect");
});

test("setup: with nothing picked, empty hexes do nothing", () => {
  assert.equal(setupIntent({ hex: 60, unit: null, selectedUnitId: null }), "none");
  assert.equal(setupIntent({ hex: null, unit: null, selectedUnitId: null }), "none");
});

