// [unit] The "✨ Smart Setup" library and picker: every setup in the pool is
// a whole, legal army with its king safe and its elephants in front; no pick
// repeats one of the last ten; "Place All" keeps what the player placed.
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  SMART_SETUPS, RECENT_WINDOW, RECENT_KEY, SMART_LABELS,
  smartSetupMode, smartLineup, eligible, completeAround, recentPicks, rememberPick
} from "cyvasse/smart_setup";
import { openingLineup } from "cyvasse/openings";
import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { parseLineup } from "cyvasse/setups";
import { COMPUTER_ZONE, PLAYER_ZONE, hexAt } from "cyvasse/board";
import { legalActions } from "cyvasse/rules";
import { UNIT_TYPES, ARMY } from "cyvasse/units";
import { seeded } from "./support/fixtures.js";

const memoryStorage = () => {
  const data = new Map();
  return { getItem: (k) => data.get(k) ?? null, setItem: (k, v) => data.set(k, String(v)) };
};

const kingStruck = (game) => {
  const king = game.teamUnits(PLAYER).find((u) => u.type.codename === "king").hex;
  const pieces = new Map(game.teamUnits(PLAYER).map((u) => [u.hex, { team: PLAYER, type: u.type }]));
  return COMPUTER_ZONE.filter((hex) => {
    const position = { pieceAt: (i) => (i === hex ? { team: COMPUTER, type: UNIT_TYPES.dragon } : pieces.get(i)) };
    return legalActions(position, hex).attacks.includes(king);
  });
};

test("the pool holds at least twelve distinct setups", () => {
  assert.ok(SMART_SETUPS.length >= 12, `${SMART_SETUPS.length} setups`);
  assert.ok(SMART_SETUPS.length > RECENT_WINDOW, "more setups than the no-repeat window");
  assert.equal(new Set(SMART_SETUPS.map(openingLineup)).size, SMART_SETUPS.length);
});

test("every setup is the whole army on the player's rows, king safe, elephants in front", () => {
  for (const setup of SMART_SETUPS) {
    const game = new Game({ rng: seeded(1) });
    game.loadLineup(openingLineup(setup));
    assert.ok(game.readyToStart, setup.slug);
    assert.ok(game.teamUnits(PLAYER).every((u) => PLAYER_ZONE.includes(u.hex)), setup.slug);
    assert.deepEqual(kingStruck(game), [], `${setup.slug}: the king falls to a first-turn dragon`);
    const elephants = game.teamUnits(PLAYER).filter((u) => u.type.codename === "elephant");
    assert.ok(elephants.every((u) => hexAt(u.hex).y === 7), `${setup.slug}: elephants on the front row`);
  }
});

test("the King's Gambit, whose king is open, is not in the pool", () => {
  assert.ok(!SMART_SETUPS.some((s) => s.slug === "kings-gambit"));
});

test("no pick repeats any of the last ten, over many games", () => {
  const storage = memoryStorage();
  const rng = seeded(7);
  let recent = recentPicks(storage);
  const picks = [];
  for (let game = 0; game < 300; game++) {
    const { opening } = smartLineup([], { recent, rng });
    picks.push(opening.slug);
    recent = rememberPick(recent, opening.slug, storage);
  }
  for (let i = 0; i < picks.length; i++) {
    const window = picks.slice(Math.max(0, i - RECENT_WINDOW), i);
    assert.ok(!window.includes(picks[i]), `pick ${i} (${picks[i]}) repeats one of ${window}`);
  }
  assert.deepEqual(recentPicks(storage), picks.slice(-RECENT_WINDOW));
  assert.equal(new Set(picks).size, SMART_SETUPS.length, "every setup comes up");
});

test("the remembered list keeps the ten newest, oldest first, under one key", () => {
  const storage = memoryStorage();
  let recent = [];
  for (const setup of SMART_SETUPS.slice(0, 12)) recent = rememberPick(recent, setup.slug, storage);
  assert.deepEqual(recent, SMART_SETUPS.slice(2, 12).map((s) => s.slug));
  assert.deepEqual(JSON.parse(storage.getItem(RECENT_KEY)), recent);
  assert.deepEqual(eligible(recent).map((s) => s.slug), SMART_SETUPS.filter((s) => !recent.includes(s.slug)).map((s) => s.slug));
});

test("refused or garbled storage still picks, and the caller's list still counts", () => {
  const refusing = { getItem: () => { throw new Error("denied") }, setItem: () => { throw new Error("denied") } };
  assert.deepEqual(recentPicks(refusing), []);
  assert.deepEqual(recentPicks({ getItem: () => "{not json", setItem() {} }), []);
  assert.deepEqual(rememberPick(["a"], "b", refusing), ["a", "b"]);
});

test("the button's label follows how much of the army is placed", () => {
  assert.equal(smartSetupMode(0, 19), "smart");
  assert.equal(smartSetupMode(1, 19), "fill");
  assert.equal(smartSetupMode(18, 19), "fill");
  assert.equal(smartSetupMode(19, 19), "new");
  assert.deepEqual(SMART_LABELS, { smart: "✨ Smart Setup", fill: "✨ Place All", new: "✨ New Setup" });
});

const armyOf = (game) => game.teamUnits(PLAYER);

test("Place All keeps the units the player placed and places the rest", () => {
  const rng = seeded(11);
  for (let trial = 0; trial < 200; trial++) {
    const game = new Game({ rng });
    const count = 1 + Math.floor(rng() * (ARMY.length - 1));
    const hexes = [...PLAYER_ZONE].sort(() => rng() - 0.5);
    const units = armyOf(game).sort(() => rng() - 0.5).slice(0, count);
    units.forEach((u, i) => game.place(u.id, hexes[i]));
    const before = new Map(units.map((u) => [u.index, u.hex]));

    const { lineup } = smartLineup(armyOf(game), { rng });
    game.loadLineup(lineup);
    assert.ok(game.readyToStart, `trial ${trial}`);
    for (const [index, hex] of before) assert.equal(game.unit(`${PLAYER}-${index}`).hex, hex, `trial ${trial}: unit ${index} moved`);
  }
});

test("placements that match a setup are finished as that setup", () => {
  const setup = SMART_SETUPS[3];
  const game = new Game({ rng: seeded(3) });
  const pairs = parseLineup(openingLineup(setup));
  for (const [index, hex] of pairs.slice(0, 6)) game.place(`${PLAYER}-${index}`, hex);
  const plan = completeAround(armyOf(game), setup);
  assert.equal(plan.displaced, 0);
  assert.equal(plan.lineup, openingLineup(setup));
  const picked = smartLineup(armyOf(game), { rng: seeded(4) });
  assert.equal(picked.lineup, openingLineup(setup), "the best fit wins");
});

test("a unit whose hex is taken goes to the nearest free hex", () => {
  const setup = SMART_SETUPS[0];
  const pairs = parseLineup(openingLineup(setup));
  const game = new Game({ rng: seeded(5) });
  const [kingIndex, kingHex] = pairs.find(([index]) => ARMY[index - 1] === "king");
  const rabble = pairs.find(([index]) => ARMY[index - 1] === "rabble")[0];
  game.place(`${PLAYER}-${rabble}`, kingHex);
  const plan = completeAround(armyOf(game), setup);
  assert.equal(plan.displaced, 1);
  const placedKing = parseLineup(plan.lineup).find(([index]) => index === kingIndex)[1];
  assert.notEqual(placedKing, kingHex);
  const d = (a, b) => Math.hypot(hexAt(a).x - hexAt(b).x, hexAt(a).y - hexAt(b).y);
  assert.ok(d(placedKing, kingHex) < 2.5, `king landed ${placedKing}, far from ${kingHex}`);
  new Game().loadLineup(plan.lineup);
});
