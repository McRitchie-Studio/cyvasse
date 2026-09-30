// [unit] Where the board key's panel opens (cyvasse/board_key): below its
// "?" when it fits, else on the roomier side, capped to that room. The
// numbers are the production audit's 390x844 match page (#3).
import { test } from "node:test";
import assert from "node:assert/strict";

import { placeKey, GAP, MARGIN } from "cyvasse/board_key";

test("a key that fits below its toggle opens below, uncapped", () => {
  assert.deepEqual(placeKey({ toggleTop: 200, toggleBottom: 218, viewportHeight: 844, navBottom: 102, panelHeight: 300 }),
    { placement: "below", maxHeight: null });
});

test("the audit's phone: no room below the timer card, so it opens up over the board", () => {
  assert.deepEqual(placeKey({ toggleTop: 640, toggleBottom: 658, viewportHeight: 844, navBottom: 102, panelHeight: 304 }),
    { placement: "above", maxHeight: null });
});

test("too tall for either side: the roomier side, capped to it", () => {
  const up = placeKey({ toggleTop: 300, toggleBottom: 318, viewportHeight: 390, navBottom: 60, panelHeight: 400 });
  assert.deepEqual(up, { placement: "above", maxHeight: 300 - 60 - GAP - MARGIN });

  const down = placeKey({ toggleTop: 80, toggleBottom: 98, viewportHeight: 390, navBottom: 60, panelHeight: 400 });
  assert.deepEqual(down, { placement: "below", maxHeight: 390 - 98 - GAP - MARGIN });
});

test("the room above stops at the navbar, and a scrolled-away navbar gives none back", () => {
  assert.equal(placeKey({ toggleTop: 300, toggleBottom: 318, viewportHeight: 390, navBottom: 150, panelHeight: 400 }).maxHeight,
    300 - 150 - GAP - MARGIN);
  assert.equal(placeKey({ toggleTop: 300, toggleBottom: 318, viewportHeight: 390, navBottom: -40, panelHeight: 400 }).maxHeight,
    300 - GAP - MARGIN);
});
