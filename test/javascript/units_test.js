// [unit] The threat groups (cyvasse/units): which units the Ranged and Melee
// switches cover.
import { test } from "node:test";
import assert from "node:assert/strict";

import { UNIT_TYPES, RANGED_UNITS, THREAT_GROUPS } from "cyvasse/units";

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
