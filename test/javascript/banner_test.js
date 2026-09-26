// [unit] The board's banner: a newer banner is never hidden by an older one's
// timer, a banner that slid out is hidden again, and the pass notice.
import { test } from "node:test";
import assert from "node:assert/strict";

import { Banner, BANNER_MS, LEAVE_MS, passNotice } from "cyvasse/banner";

// A stand-in for the banner element: the three things Banner touches.
function fakeNode() {
  const classes = new Set();
  return {
    textContent: "",
    hidden: true,
    classList: {
      add: (...names) => names.forEach((n) => classes.add(n)),
      remove: (...names) => names.forEach((n) => classes.delete(n)),
      contains: (name) => classes.has(name)
    }
  };
}

// A hand-cranked clock, so the test says exactly when time passes.
function fakeClock() {
  let now = 0;
  let nextId = 1;
  const pending = new Map();
  return {
    schedule: (fn, ms) => {
      const id = nextId++;
      pending.set(id, { at: now + ms, fn });
      return id;
    },
    cancel: (id) => pending.delete(id),
    advance(ms) {
      const until = now + ms;
      for (;;) {
        const due = [...pending].filter(([, t]) => t.at <= until).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        pending.delete(due[0]);
        now = due[1].at;
        due[1].fn();
      }
      now = until;
    }
  };
}

function showing(node) {
  return !node.hidden && node.classList.contains("is-showing") && !node.classList.contains("is-leaving");
}

test("a staying banner is not slid away by the turn banner it replaced", () => {
  const node = fakeNode();
  const clock = fakeClock();
  const banner = new Banner(node, clock);

  banner.show("Turn 12 · Your move");
  clock.advance(BANNER_MS / 2);
  banner.show("You win, at turn 12.", null, { stay: true });
  clock.advance(BANNER_MS * 3);

  assert.equal(node.textContent, "You win, at turn 12.");
  assert.ok(showing(node), "the win stays up");
});

test("a banner slides out, runs its hand-over, and is then hidden", () => {
  const node = fakeNode();
  const clock = fakeClock();
  const banner = new Banner(node, clock);
  let handedOver = 0;

  banner.show("You have the first move.", () => handedOver++);
  assert.ok(showing(node));
  clock.advance(BANNER_MS);
  assert.equal(handedOver, 1);
  assert.ok(node.classList.contains("is-leaving"));
  assert.equal(node.hidden, false, "still sliding out");
  clock.advance(LEAVE_MS);
  assert.equal(node.hidden, true);
  assert.ok(!node.classList.contains("is-leaving"));
});

test("a replaced banner's hand-over does not run", () => {
  const node = fakeNode();
  const clock = fakeClock();
  const banner = new Banner(node, clock);
  let ran = false;

  banner.show("Turn 3 · Your move", () => { ran = true; });
  banner.hide();
  clock.advance(BANNER_MS * 2);
  assert.equal(ran, false);
  assert.equal(node.hidden, true);
});

test("pace scales both delays", () => {
  const node = fakeNode();
  const clock = fakeClock();
  const banner = new Banner(node, { ...clock, pace: () => 0 });
  banner.show("Turn 1 · Your move");
  clock.advance(0);
  assert.equal(node.hidden, true);
});

test("the pass notice names who had no move", () => {
  assert.equal(passNotice(1, "Qavo"), "You have no legal move, so your turn passes.");
  assert.equal(passNotice(0, "Qavo"), "Qavo has no legal move and passes.");
});
