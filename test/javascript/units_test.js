// [unit] The threat groups (cyvasse/units): which units the Ranged and Melee
// switches cover.
import { test } from "node:test";
import assert from "node:assert/strict";

import { UNIT_TYPES, RANGED_UNITS, THREAT_GROUPS, SIZE_TIERS, SIZE_TIER_UNITS } from "cyvasse/units";

test("every unit lands in exactly one threat group", () => {
  const groups = Object.fromEntries(Object.values(UNIT_TYPES).map((type) => [type.codename, type.threatGroup]));
  assert.deepEqual(groups, {
    rabble: "melee",
    spearman: "melee",
    elephant: "melee",
    lighthorse: "melee",
    heavyhorse: "melee",
    crossbowman: "ranged",
    trebuchet: "ranged",
    catapult: "ranged",
    dragon: "melee",
    king: "melee",
    mountain: "melee"
  });
  assert.deepEqual(THREAT_GROUPS, ["ranged", "melee"]);
});

test("the ranged list names only real units, and every unit of the range rank", () => {
  for (const codename of RANGED_UNITS) assert.ok(UNIT_TYPES[codename], `${codename} is a unit`);
  const rangeRank = Object.values(UNIT_TYPES).filter((type) => type.rank === "range").map((type) => type.codename);
  assert.deepEqual([...RANGED_UNITS].sort(), rangeRank.sort());
});

// [unit] The board's size tiers (cyvasse/units sizeTier), which game.css
// scales the art by: every unit sits in exactly one tier, and the tiers are
// the ones Alex named.
test("every unit maps to exactly one size tier", () => {
  const tiers = Object.fromEntries(Object.values(UNIT_TYPES).map((type) => [type.codename, type.sizeTier]));
  assert.deepEqual(tiers, {
    rabble: "small",
    spearman: "small",
    crossbowman: "small",
    king: "medium",
    lighthorse: "medium",
    heavyhorse: "medium",
    trebuchet: "large",
    catapult: "large",
    elephant: "large",
    dragon: "large",
    mountain: "large"
  });
  assert.deepEqual(SIZE_TIERS, ["small", "medium", "large"]);
  // The tier lists partition the units: none missing, none listed twice.
  assert.deepEqual(Object.keys(SIZE_TIER_UNITS), SIZE_TIERS);
  const listed = Object.values(SIZE_TIER_UNITS).flat();
  assert.deepEqual([...listed].sort(), Object.keys(UNIT_TYPES).sort());
});

// [unit] Alex's stats of September 29, 2026 (cyvasse-stats-and-trumps-v3,
// with his 21:48 MDT change: the spearman trumps nothing). Strength is every
// unit's attack; it defends at the same number, except the three range units,
// which defend at 1. test/models/cyvasse_rules/units_parity_test.rb holds the
// Ruby table to the same rows.
test("the unit table is Alex's new stats table", () => {
  // [move, second jump, strength, range, trumps]
  const table = {
    rabble: [3, 0, 1, 0, ["king"]],
    trebuchet: [0, 0, 1, 4, ["dragon"]],
    king: [2, 0, 2, 0, ["dragon"]],
    lighthorse: [4, 1, 2, 0, []],
    crossbowman: [1, 0, 2, 2, []],
    spearman: [2, 0, 3, 0, []],
    heavyhorse: [3, 1, 3, 0, []],
    catapult: [1, 0, 3, 3, ["dragon"]],
    elephant: [2, 0, 4, 0, []],
    dragon: [10, 0, 5, 0, []]
  };
  for (const [codename, [move, second, strength, range, trump]] of Object.entries(table)) {
    const type = UNIT_TYPES[codename];
    const defence = type.rank === "range" ? 1 : strength;
    assert.deepEqual(
      [type.moveRange, type.secondJump, type.attack, type.defence, type.attackRange, [...type.trump]],
      [move, second, strength, defence, range, trump],
      codename
    );
  }
  assert.equal(UNIT_TYPES.mountain.moveRange, 0, "the mountain is unchanged: immovable");
});
