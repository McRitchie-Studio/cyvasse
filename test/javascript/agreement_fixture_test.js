// [unit] The checked-in rules record equals what the engine answers today.
// The Ruby port (app/models/cyvasse_rules) is tested against that record, so
// a JS rules change that is not regenerated (bin/rules-agreement) fails here,
// and one that is regenerated fails the Ruby lane until the port follows.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { buildAgreementFixture, serialize, SCATTER_POSITIONS, GAMES, SCENARIOS } from "./support/agreement.js";

const FILE = new URL("../fixtures/files/rules_agreement.json", import.meta.url);

test("the rules record is current: regenerate with bin/rules-agreement", () => {
  assert.equal(readFileSync(FILE, "utf8"), serialize(buildAgreementFixture()));
});

test("the record covers every unit type, both jumps, captures and finished games", () => {
  const { positions, games } = JSON.parse(readFileSync(FILE, "utf8"));
  assert.equal(positions.length, SCATTER_POSITIONS);
  assert.equal(games.length, GAMES);
  const indices = new Set(positions.flatMap((p) => p.units.map(([, index]) => index)));
  assert.equal(indices.size, 19, "every army index appears");
  assert.ok(positions.some((p) => p.actions.some(([, jump]) => jump === 2)), "second jumps");
  assert.ok(positions.some((p) => p.actions.some(([, , , attacks]) => attacks.length > 0)), "captures");
  assert.ok(games.every((g) => g.turns.at(-1).over), "every game reaches its end");
  assert.ok(games.some((g) => g.turns.some((t) => t.steps.length === 2)), "double jumps in play");
});

test("the record covers passes and draws, by either side", () => {
  const { scenarios } = JSON.parse(readFileSync(FILE, "utf8"));
  assert.equal(scenarios.length, SCENARIOS.length);
  const turns = scenarios.flatMap((s) => s.turns);
  for (const mover of [0, 1]) {
    const mine = turns.filter((t) => t.mover === mover);
    assert.ok(mine.some((t) => t.passed && !t.over && t.offense === mover), `side ${mover} moves and the other passes back`);
    assert.ok(mine.some((t) => t.passed && t.over && t.winner === null), `side ${mover} moves and the game is drawn`);
  }
  assert.ok(scenarios.filter((s) => s.name.startsWith("pass")).every((s) => s.turns.length > 1 && s.turns.every((t) => t.passed)),
    "a pass repeats every turn the boxed side cannot move");
});
