// [unit] Cyvasse Night's clock (cyvasse/night_clock): the phase at a moment,
// the countdown's parts, and the start time in the visitor's own zone.
import { test } from "node:test";
import assert from "node:assert/strict";

import { phaseAt, countdownParts, pad, localTimeLabel } from "cyvasse/night_clock";

const START = Date.parse("2026-10-06T19:00:00-06:00");
const END = START + 3 * 3600 * 1000;

test("before the start, during the window, and after it; the edges belong to the next phase", () => {
  assert.equal(phaseAt(START - 1, START, END), "before");
  assert.equal(phaseAt(START, START, END), "during");
  assert.equal(phaseAt(END - 1, START, END), "during");
  assert.equal(phaseAt(END, START, END), "after");
});

test("the countdown splits into days, hours, minutes and seconds", () => {
  const left = ((6 * 24 + 7) * 3600 + 5 * 60 + 9) * 1000;
  assert.deepEqual(countdownParts(START, START - left), { days: 6, hours: 7, minutes: 5, seconds: 9 });
  assert.deepEqual(countdownParts(START, START - 999), { days: 0, hours: 0, minutes: 0, seconds: 1 }, "rounds up");
  assert.deepEqual(countdownParts(START, START), { days: 0, hours: 0, minutes: 0, seconds: 0 });
  assert.deepEqual(countdownParts(START, START + 5000), { days: 0, hours: 0, minutes: 0, seconds: 0 }, "never negative");
});

test("two-digit parts", () => {
  assert.equal(pad(4), "04");
  assert.equal(pad(12), "12");
});

test("the start in the visitor's zone", () => {
  // The joiner between date and time (", " or " at ") varies with the ICU version.
  assert.match(localTimeLabel(START, { locale: "en-US", timeZone: "America/New_York" }), /^Tuesday, October 6(,| at) 9:00\sPM EDT$/);
  assert.match(localTimeLabel(START, { locale: "en-GB", timeZone: "Europe/London" }), /Wednesday.*7 October.*02:00/);
});
