// [unit] How far a setup scroll moves the page (cyvasse/setup_fit), the
// decision the /play and /matches board controllers act on as setup opens
// and at each pick (task cyvasse-dock-landscape-tablet).
import { test } from "node:test";
import assert from "node:assert/strict";

import { setupScrollBy, SETUP_FIT_MARGIN } from "cyvasse/setup_fit";

const M = SETUP_FIT_MARGIN;

test("a desktop, with no fit, never scrolls", () => {
  assert.equal(setupScrollBy({ fit: "", board: { top: 300, bottom: 1300 }, army: { top: 200, bottom: 600 }, pinned: 80, viewportHeight: 800 }), 0);
  assert.equal(setupScrollBy({ fit: "sideways", board: { top: 300, bottom: 1300 }, army: { top: 0, bottom: 0 }, viewportHeight: 800 }), 0);
});

test("a board already on the screen is left where it is", () => {
  // bottom sheet: the board above the sheet's top
  assert.equal(setupScrollBy({ fit: "bottom", board: { top: 120, bottom: 700 }, army: { top: 710, bottom: 1180 }, pinned: 100, viewportHeight: 1180 }), 0);
  // side sheet: the board above the screen's foot
  assert.equal(setupScrollBy({ fit: "side", board: { top: 60, bottom: 380 }, army: { top: 53, bottom: 390 }, pinned: 53, viewportHeight: 390 }), 0);
  // page: the board and the card both on the screen
  assert.equal(setupScrollBy({ fit: "page", board: { top: 190, bottom: 780 }, army: { top: 100, bottom: 540 }, pinned: 53, viewportHeight: 820 }), 0);
});

test("a board under the bottom sheet is centred above it", () => {
  const by = setupScrollBy({ fit: "bottom", board: { top: 319, bottom: 948 }, army: { top: 930, bottom: 1180 }, pinned: 131, viewportHeight: 1180 });
  const top = 131 + M;
  const room = 930 - M - top;
  assert.equal(by, 319 - (top + (room - 629) / 2));
  assert.ok(319 - by >= top && 948 - by <= 930 - M, "the board lands between the navbar and the sheet");
});

test("the side sheet's board is measured against the screen's foot, not the sheet", () => {
  // The side sheet's top is the navbar's bottom; the board must reach the foot.
  const by = setupScrollBy({ fit: "side", board: { top: -455, bottom: -133 }, army: { top: 53, bottom: 390 }, pinned: 53, viewportHeight: 390 });
  assert.ok(by < 0, "a board above the screen scrolls up to it");
  assert.ok(-455 - by >= 53 + M && -133 - by <= 390 - M);
});

test("page: the board and the army card are kept on the screen together", () => {
  const board = { top: 319, bottom: 948 };
  const army = { top: 231, bottom: 672 };
  const by = setupScrollBy({ fit: "page", board, army, pinned: 53, viewportHeight: 820 });
  assert.ok(army.top - by >= 53 + M, "the card's top clears the navbar");
  assert.ok(board.bottom - by <= 820 - M, "the board's foot is on the screen");
});

test("a box taller than the room lines up its foot first", () => {
  // The expanded navbar leaves too little room; its collapse makes the rest.
  assert.equal(setupScrollBy({ fit: "page", board: { top: 319, bottom: 948 }, army: { top: 231, bottom: 672 }, pinned: 131, viewportHeight: 820 }), 948 - (820 - M));
});

test("a sub-pixel miss is no scroll", () => {
  assert.equal(setupScrollBy({ fit: "side", board: { top: 57.2, bottom: 386.9 }, army: { top: 0, bottom: 0 }, pinned: 53, viewportHeight: 390 }), 0);
});
