// [unit] The twenty-five opening lineups in the setup panel: each is a whole army
// on the player's rows that Game#loadLineup accepts, and each keeps the
// promise its description makes about the king, checked with the real rules.
import { test } from "node:test";
import assert from "node:assert/strict";

import { OPENINGS, openingLineup } from "cyvasse/openings";
import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { COMPUTER_OPPONENTS, parseLineup } from "cyvasse/setups";
import { COMPUTER_ZONE, hexAt } from "cyvasse/board";
import { legalActions } from "cyvasse/rules";
import { UNIT_TYPES, typeAt } from "cyvasse/units";
import { seeded } from "./support/fixtures.js";

const ROW_WIDTHS = [10, 9, 8, 7, 6];

const loaded = (opening) => {
  const game = new Game({ rng: seeded(1) });
  game.loadLineup(openingLineup(opening));
  return game;
};

const kingHex = (game) => game.teamUnits(PLAYER).find((u) => u.type.codename === "king").hex;

test("there are twenty-five openings with distinct slugs and names", () => {
  assert.equal(OPENINGS.length, 25);
  assert.equal(new Set(OPENINGS.map((o) => o.slug)).size, 25);
  assert.equal(new Set(OPENINGS.map((o) => o.name)).size, 25);
  for (const opening of OPENINGS) assert.ok(opening.idea.length > 40, `${opening.slug} explains itself`);
});

test("every opening draws the five rows at their true widths", () => {
  for (const { slug, rows } of OPENINGS) {
    assert.deepEqual(rows.map((row) => row.length), ROW_WIDTHS, slug);
  }
});

test("every opening loads as the whole army on the player's rows", () => {
  for (const opening of OPENINGS) {
    const game = loaded(opening);
    assert.ok(game.readyToStart, opening.slug);
    assert.equal(game.playerLineup(), openingLineup(opening), opening.slug);
  }
});

test("a letter lands on the hex its row and position name", () => {
  const iron = OPENINGS.find((o) => o.slug === "iron-corner");
  const game = loaded(iron);
  assert.equal(game.pieceAt(86).type.codename, "king", "back row, first hex");
  assert.equal(game.pieceAt(52).type.codename, "mountain", "front row, first hex");
  assert.equal(game.pieceAt(56).type.codename, "trebuchet", "front row, fifth hex");
});

test("no two openings are the same lineup", () => {
  assert.equal(new Set(OPENINGS.map(openingLineup)).size, OPENINGS.length);
});

// The first-turn dragon strike: an enemy dragon on any hex of their five
// rows, with our whole army on the board, cannot capture our king. The
// King's Gambit alone leaves its forward diagonals open, and says so.
test("every opening but the King's Gambit keeps its king out of a first-turn dragon strike", () => {
  for (const opening of OPENINGS) {
    const game = loaded(opening);
    const king = kingHex(game);
    const pieces = new Map(game.teamUnits(PLAYER).map((u) => [u.hex, { team: PLAYER, type: u.type }]));
    const struck = COMPUTER_ZONE.filter((hex) => {
      const position = { pieceAt: (i) => (i === hex ? { team: COMPUTER, type: UNIT_TYPES.dragon } : pieces.get(i)) };
      return legalActions(position, hex).attacks.includes(king);
    });
    if (opening.slug === "kings-gambit") {
      assert.ok(struck.length > 0, "the gambit's open diagonals are real");
    } else {
      assert.deepEqual(struck, [], `${opening.slug}: a dragon on ${struck} takes the king`);
    }
  }
});

// "The side whose king stands nearer the middle row moves first."
test("Crown Forward and the King's Gambit move first against every computer army", () => {
  for (const slug of ["crown-forward", "kings-gambit"]) {
    const opening = OPENINGS.find((o) => o.slug === slug);
    for (const { name, lineups } of COMPUTER_OPPONENTS) {
      for (const lineup of lineups) {
        const game = new Game({ rng: seeded(2), computer: { name, lineup } });
        game.loadLineup(openingLineup(opening));
        game.start();
        assert.equal(game.offense, PLAYER, `${slug} vs ${name}: ${lineup}`);
      }
    }
  }
});

test("the King's Gambit king stands on the front row and Crown Forward's on the second", () => {
  const row = (slug) => hexAt(kingHex(loaded(OPENINGS.find((o) => o.slug === slug)))).y;
  assert.equal(row("kings-gambit"), 7);
  assert.equal(row("crown-forward"), 8);
});

test("the computer lineups the first-move test reads keep their kings on the top rows", () => {
  const kingIndex = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19].find((i) => typeAt(i).codename === "king");
  for (const { lineups } of COMPUTER_OPPONENTS) {
    for (const lineup of lineups) {
      const hex = parseLineup(lineup).find(([index]) => index === kingIndex)[1];
      assert.ok(hexAt(hex).y <= 3, `king on hex ${hex}`);
    }
  }
});

// Grey Wall and Crossbow Ambush make claims about who takes an elephant; the
// capture rules answer them, so a change to either shows up here.
test("what the openings say about elephants is what the rules do", () => {
  const takes = (attacker, defender) => {
    const position = { pieceAt: (i) => ({ 60: { team: PLAYER, type: UNIT_TYPES[attacker] }, 50: { team: COMPUTER, type: UNIT_TYPES[defender] } })[i] };
    const { attacks } = legalActions(position, 60);
    // A shooter takes from range; everyone else by stepping onto the hex.
    return attacks.includes(50);
  };
  const elephantTakers = Object.keys(UNIT_TYPES).filter((codename) => takes(codename, "elephant")).sort();
  assert.deepEqual(elephantTakers, ["crossbowman", "dragon", "elephant"]);
  assert.match(OPENINGS.find((o) => o.slug === "grey-wall").idea, /a dragon, a crossbow or another elephant/);

  assert.equal(takes("elephant", "crossbowman"), false, "an elephant cannot take a crossbow");
  assert.equal(takes("crossbowman", "elephant"), true, "a crossbow can take an elephant");
  assert.match(OPENINGS.find((o) => o.slug === "crossbow-ambush").idea, /a crossbow, which it cannot take and which can take it/);
});
