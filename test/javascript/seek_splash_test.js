// [unit] The Play Now splash's timing: the ring's seconds, and the gate that
// starts the splash at once but opens the game only once the splash has run
// and the server has named the match.
import { test } from "node:test";
import assert from "node:assert/strict";

import { secondsLeft, SplashGate } from "cyvasse/seek_splash";

test("the ring counts whole seconds up, and reads 0 the instant the search ends", () => {
  assert.equal(secondsLeft(20_000, 0), 20);
  assert.equal(secondsLeft(20_000, 19_001), 1);
  assert.equal(secondsLeft(20_000, 19_999), 1);
  assert.equal(secondsLeft(20_000, 20_000), 0);
  assert.equal(secondsLeft(20_000, 25_000), 0);
});

test("the splash starts once, however many things start it", () => {
  const gate = new SplashGate(5000);
  assert.equal(gate.started, false);
  assert.equal(gate.start(100), true);
  assert.equal(gate.start(900), false);
  assert.equal(gate.started, true);
});

test("the game waits for the server to name the match", () => {
  const gate = new SplashGate(5000);
  gate.start(0);
  assert.equal(gate.wait(9000), null);
  gate.arrive("/matches/7");
  assert.equal(gate.wait(9000), 0);
});

test("a match named early still waits out the splash, timed from its start", () => {
  const gate = new SplashGate(5000);
  gate.start(1000);
  gate.arrive("/matches/7");
  assert.equal(gate.wait(1200), 4800);
  assert.equal(gate.wait(6000), 0);
});

test("a match named before the splash starts waits for it", () => {
  const gate = new SplashGate(5000);
  gate.arrive("/matches/7");
  assert.equal(gate.wait(0), null);
  gate.start(0);
  assert.equal(gate.wait(0), 5000);
});

test("the first match named is the one opened", () => {
  const gate = new SplashGate(5000);
  gate.arrive("/matches/7");
  gate.arrive("/matches/8");
  assert.equal(gate.url, "/matches/7");
});
