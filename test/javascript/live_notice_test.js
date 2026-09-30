// [unit] The live match's strike and seat notice: which line shows, which one
// only "Take back my seat" ends, and none once the match is over.
import { test } from "node:test";
import assert from "node:assert/strict";

import { liveNotice } from "cyvasse/live_notice";

const live = (overrides = {}) => ({
  taken_over: { you: false, opponent: false },
  took_back: { you: false, opponent: false },
  auto_set_up: { you: false, opponent: false },
  strikes: { you: 0, opponent: 0 },
  ...overrides
});

test("no live block, or nothing missed, is no notice", () => {
  assert.deepEqual(liveNotice(null, "play", "Qavo"), { text: "", held: false });
  assert.deepEqual(liveNotice(live(), "play", "Qavo"), { text: "", held: false });
});

test("a seat the computer holds is held; the rest can be dismissed", () => {
  const held = liveNotice(live({ taken_over: { you: true, opponent: false } }), "play", "Qavo");
  assert.equal(held.held, true);
  assert.match(held.text, /has taken your seat/);

  const back = liveNotice(live({ took_back: { you: true, opponent: false }, strikes: { you: 1, opponent: 0 } }), "play", "Qavo");
  assert.equal(back.held, false);
  assert.equal(back.text, "You took back your seat. Miss one more clock and a computer player takes it again.");

  assert.equal(liveNotice(live({ strikes: { you: 0, opponent: 1 } }), "play", "Qavo").text, "Qavo missed a clock.");
});

test("a finished match shows no seat or strike notice, whatever the clocks said", () => {
  const every = live({
    taken_over: { you: true, opponent: true },
    took_back: { you: true, opponent: true },
    auto_set_up: { you: true, opponent: true },
    strikes: { you: 1, opponent: 1 }
  });
  assert.deepEqual(liveNotice(every, "over", "Qavo"), { text: "", held: false });
  assert.deepEqual(liveNotice(live({ took_back: { you: true, opponent: false } }), "over", "Qavo"), { text: "", held: false });
  // The same state in play does show: the guard is the phase, not the data.
  assert.notEqual(liveNotice(every, "play", "Qavo").text, "");
});
