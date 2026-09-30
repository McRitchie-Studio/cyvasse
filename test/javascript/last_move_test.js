// [unit] The last-move mark's clock (cyvasse/last_move): it belongs to the
// move, not to a redraw, and clears ten seconds after the move lands.
import { test, mock } from "node:test";
import assert from "node:assert/strict";

import { LastMoveMarker, LAST_MOVE_MS, lastMoveKey } from "cyvasse/last_move";

function clock() {
  mock.timers.enable({ apis: ["setTimeout", "Date"], now: 0 });
  return () => mock.timers.reset();
}

test("the mark lasts ten seconds", () => {
  assert.equal(LAST_MOVE_MS, 10_000);
});

test("a move is marked, then cleared ten seconds after it lands", () => {
  const done = clock();
  try {
    let expired = 0;
    const marker = new LastMoveMarker({ onExpire: () => { expired += 1; } });
    assert.deepEqual(marker.mark("48,58", [48, 58]), { hexes: [48, 58], elapsed: 0 });
    mock.timers.tick(9_999);
    assert.equal(expired, 0);
    assert.deepEqual(marker.mark("48,58", [48, 58]).hexes, [48, 58], "still marked just before ten seconds");
    mock.timers.tick(1);
    assert.equal(expired, 1, "cleared at ten seconds");
    assert.deepEqual(marker.mark("48,58", [48, 58]), { hexes: [], elapsed: LAST_MOVE_MS }, "a redraw of the same move does not bring it back");
    mock.timers.tick(60_000);
    assert.equal(expired, 1, "once per move");
  } finally {
    done();
  }
});

test("a redraw partway through keeps the move's clock and says how far it has run", () => {
  const done = clock();
  try {
    let expired = 0;
    const marker = new LastMoveMarker({ onExpire: () => { expired += 1; } });
    marker.mark("48,58", [48, 58]);
    mock.timers.tick(4_000);
    assert.deepEqual(marker.mark("48,58", [48, 58]), { hexes: [48, 58], elapsed: 4_000 });
    mock.timers.tick(6_000);
    assert.equal(expired, 1, "ten seconds from the move, not from the redraw");
  } finally {
    done();
  }
});

test("a new move restarts the clock; no move clears the mark", () => {
  const done = clock();
  try {
    let expired = 0;
    const marker = new LastMoveMarker({ onExpire: () => { expired += 1; } });
    marker.mark("48,58", [48, 58]);
    mock.timers.tick(8_000);
    assert.deepEqual(marker.mark("59,69", [59, 69]), { hexes: [59, 69], elapsed: 0 });
    mock.timers.tick(8_000);
    assert.equal(expired, 0, "the first move's timer is gone");
    mock.timers.tick(2_000);
    assert.equal(expired, 1);

    marker.mark("12,23", [12, 23]);
    assert.deepEqual(marker.mark("", []), { hexes: [], elapsed: 0 }, "a new game: nothing marked");
    mock.timers.tick(20_000);
    assert.equal(expired, 1, "and nothing left to fire");
  } finally {
    done();
  }
});

test("stop cancels a pending clear", () => {
  const done = clock();
  try {
    let expired = 0;
    const marker = new LastMoveMarker({ onExpire: () => { expired += 1; } });
    marker.mark("48,58", [48, 58]);
    marker.stop();
    mock.timers.tick(20_000);
    assert.equal(expired, 0);
  } finally {
    done();
  }
});

test("the key names the move by its hexes, utility move included, not the turn", () => {
  assert.equal(lastMoveKey({ lastMove: [48, 58] }), "48,58");
  assert.equal(lastMoveKey({ lastMove: [48, 58], utilMove: 12 }), "48,58,12");
  assert.equal(lastMoveKey({ lastMove: [58, 48] }), "58,48", "the way back is a new move");
  assert.equal(lastMoveKey({ lastMove: [], utilMove: null }), "");
  assert.equal(lastMoveKey({ lastMove: [48, 58], turn: 3 }), lastMoveKey({ lastMove: [48, 58], turn: 4 }), "a pass does not relight it");
});
