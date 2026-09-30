// [unit] The "✨ Smart Setup" library and picker: every setup in the pool is
// a whole, legal army with its king safe from every enemy first turn
// (cyvasse/king_safety) and its elephants in front; no pick repeats one of the
// last ten; "Place All" keeps what the player placed and, wherever the
// player's own placements allow it, leaves the king safe.
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  smartSetups, armyOf as lineupArmy, RECENT_WINDOW, RECENT_KEY, SMART_LABELS,
  smartSetupMode, smartLineup, eligible, completeAround, recentPicks, rememberPick
} from "cyvasse/smart_setup";
import { OPENINGS, openingLineup } from "cyvasse/openings";
import { Game, PLAYER, COMPUTER, shuffle } from "cyvasse/game";
import { parseLineup } from "cyvasse/setups";
import { COMPUTER_ZONE, PLAYER_ZONE, hexAt } from "cyvasse/board";
import { legalActions } from "cyvasse/rules";
import { UNIT_TYPES, ARMY } from "cyvasse/units";
import { kingSafe, kingThreats } from "cyvasse/king_safety";
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
  assert.ok(smartSetups().length >= 12, `${smartSetups().length} setups`);
  assert.ok(smartSetups().length > RECENT_WINDOW, "more setups than the no-repeat window");
  assert.equal(new Set(smartSetups().map(openingLineup)).size, smartSetups().length);
});

test("every setup is the whole army on the player's rows, king safe, elephants in front", () => {
  for (const setup of smartSetups()) {
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
  assert.ok(!smartSetups().some((s) => s.slug === "kings-gambit"));
});

// Task cyvasse-smart-setup-king-safety: about one Smart Setup in six lost its
// king to the computer's first move. The pool is exactly the openings that
// pass the king-safety check and put both elephants in front.
test("the pool is every king-safe opening with both elephants in front, and nothing else", () => {
  const front = (o) => [...o.rows[0]].filter((c) => c === "E").length === 2;
  const expected = OPENINGS.filter((o) => front(o) && kingSafe(lineupArmy(openingLineup(o)))).map((o) => o.slug);
  assert.deepEqual(smartSetups().map((o) => o.slug), expected);
  for (const setup of smartSetups()) assert.deepEqual(kingThreats(lineupArmy(openingLineup(setup))), [], setup.slug);
  assert.ok(!smartSetups().some((s) => s.slug === "crown-forward"), "Crown Forward's king stands forward on purpose");
  assert.ok(smartSetups().length >= 19, `${smartSetups().length} setups: all but the two forward kings`);
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
  assert.equal(new Set(picks).size, smartSetups().length, "every setup comes up");
});

test("the remembered list keeps the ten newest, oldest first, under one key", () => {
  const storage = memoryStorage();
  let recent = [];
  for (const setup of smartSetups().slice(0, 12)) recent = rememberPick(recent, setup.slug, storage);
  assert.deepEqual(recent, smartSetups().slice(2, 12).map((s) => s.slug));
  assert.deepEqual(JSON.parse(storage.getItem(RECENT_KEY)), recent);
  assert.deepEqual(eligible(recent).map((s) => s.slug), smartSetups().filter((s) => !recent.includes(s.slug)).map((s) => s.slug));
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
  assert.deepEqual(SMART_LABELS, { smart: "Smart Setup", fill: "Place All", new: "New Setup" });
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
  const setup = smartSetups()[3];
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
  const setup = smartSetups()[0];
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

// The units that stop a dragon's flight (rules.js dragonCode): a shooter or
// the dragon. Nothing else on its line matters to it.
const STOPPERS = ["crossbowman", "trebuchet", "catapult", "dragon"];

// Whether no fill at all could have kept the king safe, proven one of two
// ways. With one or two units in the dock, by trying every arrangement of
// them on the free hexes. With more, only when none of them stops a dragon
// and every free hex is on an open dragon line whatever else stands there
// (the player's shooters and dragon alone decide the dragon's lines).
function beyondSaving(game) {
  const placed = game.teamUnits(PLAYER, "alive").map((u) => ({ hex: u.hex, type: u.type }));
  const docked = game.teamUnits(PLAYER).filter((u) => u.status !== "alive");
  const free = PLAYER_ZONE.filter((hex) => !placed.some((u) => u.hex === hex));
  const king = docked.find((u) => u.type.codename === "king");
  const others = docked.filter((u) => u !== king);
  if (others.length <= 1) {
    return free.every((kingHex) => {
      const rest = free.filter((hex) => hex !== kingHex);
      const fills = others.length === 0 ? [[]] : rest.map((hex) => [{ hex, type: others[0].type }]);
      return fills.every((fill) => !kingSafe([...placed, ...fill, { hex: kingHex, type: king.type }]));
    });
  }
  if (others.some((u) => STOPPERS.includes(u.type.codename))) return false;
  const stoppers = placed.filter((u) => STOPPERS.includes(u.type.codename));
  return free.every((hex) => kingThreats([...stoppers, { hex, type: king.type }]).some((t) => t.attacker === "dragon"));
}

// Task cyvasse-smart-setup-king-safety. The player places some of the army
// (never the king) at random; Place All finishes it. Its king is safe unless
// the player's own placements left no safe fill; and some of the safe ones
// needed the rearranging pass (secure), since no opening's own fill was safe.
test("Place All never leaves the king open to a first-turn capture it could have closed, over 200 seeded armies", () => {
  const rng = seeded(11);
  const tally = { safe: 0, rescued: 0, hopeless: 0 };
  for (let trial = 0; trial < 200; trial++) {
    const game = new Game({ rng });
    const placeable = shuffle(armyOf(game).filter((u) => u.type.codename !== "king"), rng);
    const hexes = shuffle([...PLAYER_ZONE], rng);
    const count = 1 + Math.floor(rng() * placeable.length);
    placeable.slice(0, count).forEach((u, i) => game.place(u.id, hexes[i]));
    const before = new Map(game.teamUnits(PLAYER, "alive").map((u) => [u.index, u.hex]));

    const units = armyOf(game);
    const { lineup } = smartLineup(units, { rng });
    const after = new Map(parseLineup(lineup));
    for (const [index, hex] of before) assert.equal(after.get(index), hex, `trial ${trial}: unit ${index} moved`);
    if (kingSafe(lineupArmy(lineup))) {
      tally.safe += 1;
      if (!smartSetups().some((o) => kingSafe(lineupArmy(completeAround(units, o).lineup)))) tally.rescued += 1;
    } else {
      assert.ok(beyondSaving(game), `trial ${trial}: ${lineup} leaves the king open, and a safe fill existed`);
      tally.hopeless += 1;
    }
  }
  assert.ok(tally.safe >= 185, JSON.stringify(tally));
  assert.ok(tally.rescued > 0, `the rearranging pass saved some: ${JSON.stringify(tally)}`);
});
