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
