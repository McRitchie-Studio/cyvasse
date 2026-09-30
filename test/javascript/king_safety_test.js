// [unit] The king-safety check (cyvasse/king_safety): no enemy unit on any hex
// of the enemy's five rows can take the king on its first turn. It must catch
// the production raid (task cyvasse-smart-setup-king-safety: an enemy light
// horse takes the shooter in front of the king on its first jump and the king
// on its second), and its verdicts must agree with the Game itself playing
// every first turn out.
import { test } from "node:test";
import assert from "node:assert/strict";

import { kingThreats, kingSafe } from "cyvasse/king_safety";
import { Game, PLAYER, COMPUTER } from "cyvasse/game";
import { openingLineup, OPENINGS } from "cyvasse/openings";
import { parseLineup, formatLineup, COMPUTER_OPPONENTS } from "cyvasse/setups";
import { COMPUTER_ZONE, hexAt, neighbors } from "cyvasse/board";
import { UNIT_TYPES, typeAt, ARMY } from "cyvasse/units";
import { smartSetups } from "cyvasse/smart_setup";
import { seeded } from "./support/fixtures.js";

const armyOf = (rows) => parseLineup(openingLineup({ rows })).map(([index, hex]) => ({ hex, type: typeAt(index) }));
const KING = ARMY.indexOf("king") + 1;

// Horse Lords as it shipped with the stats of cyvasse-stats-and-trumps-v3:
// the king on the fourth row under the catapult and a crossbow, shooters
// that defend at 1.
// Production match 107969 lost its king this way in sixteen seconds.
const RAIDABLE = ["LH..EE..HL", "..S.T.S..", "M..CX..M", "R.XKD.R", "..R..."];

// A game whose computer has one unit of `codename` on `from` (and its king
// in the far corner, which every Game needs), about to play its first turn.
function soloRaid(rows, codename, from) {
  const enemyIndex = ARMY.indexOf(codename) + 1;
  const pairs = [[KING, from === 1 ? 2 : 1], [enemyIndex, from]].sort((a, b) => a[0] - b[0]);
  const game = new Game({ rng: seeded(1), computer: { name: "solo", lineup: formatLineup(pairs) } });
  game.loadLineup(openingLineup({ rows }));
  game.start();
  game.offense = COMPUTER;
  return game;
}

// Every first turn the side to move can play, played out on the Game: true
// when one of them takes the player's king.
function someFirstTurnTakesTheKing(game) {
  const kingDead = () => game.unit(`${PLAYER}-${KING}`).status === "dead";
  for (const from of game.selectableHexes()) {
    const { moves, attacks } = game.actionsFrom(from);
    for (const to of [...moves, ...attacks]) {
      const before = game.snapshot();
      const result = game.act(from, to);
      let fell = kingDead();
      if (!fell && result.secondJump) {
        const hop = game.activeHex;
        const next = game.actionsFrom(hop);
        for (const to2 of [...next.moves, ...next.attacks]) {
          const mid = game.snapshot();
          game.act(hop, to2);
          fell = kingDead();
          game.restoreSnapshot(mid);
          if (fell) break;
        }
      }
      game.restoreSnapshot(before);
      if (fell) return true;
    }
  }
  return false;
}

test("the shipped Horse Lords is raidable: a light horse takes a shooter, then the king", () => {
  const threats = kingThreats(armyOf(RAIDABLE));
  assert.ok(threats.length > 0);
  assert.equal(kingSafe(armyOf(RAIDABLE)), false);
  const king = armyOf(RAIDABLE).find((u) => u.type.codename === "king").hex;
  const raid = threats.find((t) => t.attacker === "lighthorse" && t.via != null);
  assert.ok(raid, "a light horse double jump");
  const game = soloRaid(RAIDABLE, "lighthorse", raid.from);
  const shooter = game.pieceAt(raid.via).type;
  assert.equal(shooter.rank, "range", "its first jump lands on a shooter");
  assert.equal(shooter.defence, 1);
  assert.ok(neighbors(hexAt(raid.via)).some((n) => n.index === king), "next to the king");
  const first = game.act(raid.from, raid.via);
  assert.equal(first.captured.type, shooter);
  assert.ok(first.secondJump);
  const second = game.act(raid.via, king);
  assert.equal(second.captured.type.codename, "king");
  assert.equal(game.winner, COMPUTER);
});

test("a lone enemy of any kind, on any hex its threat names, really does take the king", () => {
  const threats = kingThreats(armyOf(RAIDABLE));
  for (const { attacker, from } of threats) {
    assert.ok(someFirstTurnTakesTheKing(soloRaid(RAIDABLE, attacker, from)), `${attacker} on ${from}`);
  }
});

// The check tries each enemy unit alone on an otherwise empty half. The Game,
// playing every first turn out, must agree hex for hex: the reach pruning
// never hides a threat, and every threat is real.
test("the check agrees with the Game on every lone attacker, hex by hex", () => {
  const fixtures = [RAIDABLE, ...["iron-corner", "crown-forward", "open-skies", "kings-gambit"].map((slug) => OPENINGS.find((o) => o.slug === slug).rows)];
  for (const rows of fixtures) {
    const threats = kingThreats(armyOf(rows));
    for (const codename of Object.keys(UNIT_TYPES).filter((c) => c !== "mountain" && c !== "king")) {
      const named = new Set(threats.filter((t) => t.attacker === codename).map((t) => t.from));
      for (const from of COMPUTER_ZONE.filter((hex) => hex !== 1)) {
        const falls = someFirstTurnTakesTheKing(soloRaid(rows, codename, from));
        assert.equal(falls, named.has(from), `${rows.join("/")}: ${codename} on ${from}`);
      }
    }
  }
});

test("every opening in the Smart Setup pool survives every first turn of every computer army", () => {
  for (const opening of smartSetups()) {
    for (const { name, lineups } of COMPUTER_OPPONENTS) {
      for (const lineup of lineups) {
        const game = new Game({ rng: seeded(2), computer: { name, lineup } });
        game.loadLineup(openingLineup(opening));
        game.start();
        game.offense = COMPUTER;
        assert.equal(someFirstTurnTakesTheKing(game), false, `${opening.slug} vs ${name}: ${lineup}`);
      }
    }
  }
});

test("an army without a king is refused", () => {
  assert.throws(() => kingThreats([{ hex: 60, type: UNIT_TYPES.rabble }]), /no king/);
});

test("a threat lists the attacker, where it starts, where it first lands and the king's hex", () => {
  const [threat] = kingThreats(armyOf(RAIDABLE), { limit: 1 });
  assert.deepEqual(Object.keys(threat).sort(), ["attacker", "from", "to", "via"]);
  assert.equal(kingThreats(armyOf(RAIDABLE), { limit: 1 }).length, 1, "limit stops the count");
});
