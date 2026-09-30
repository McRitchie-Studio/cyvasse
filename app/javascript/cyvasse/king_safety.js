// Whether an army's king survives the enemy's first turn, whatever the enemy
// placed and whatever it plays.
//
// A king-safe army (task cyvasse-smart-setup-king-safety): for every enemy
// unit type on every hex of the enemy's five rows (hexes 1-40), and every
// legal first turn that unit can play against this army, the king is not
// captured. A first turn is one action: a move or capture, a shot, a dragon
// flight, or a cavalry unit's first jump followed by any second jump, from
// wherever the first jump (move or capture) left it.
//
// Testing each attacker alone, on an otherwise empty enemy half, covers
// every whole enemy army. The rest of the enemy's army can only get in its
// own attacker's way: a friend stops a walk (rules.js code 5), the dragon
// flies over friends and empty hexes alike, and a shot passes both. The
// enemy's mountains cast shadows and block walks, never open a line. So if no
// lone attacker can reach the king, no army can; and a lone attacker that can
// reach it is a real threat, since the enemy may place that unit there.
//
// It assumes the enemy moves first, whoever's king stands nearer the middle:
// an online opponent can always stand its king forward.

import { COMPUTER_ZONE } from "cyvasse/board";
import { legalActions } from "cyvasse/rules";
import { UNIT_TYPES } from "cyvasse/units";

const ATTACKERS = Object.freeze(Object.keys(UNIT_TYPES).filter((codename) => codename !== "mountain"));
const ENEMY = "enemy";

// `army` is [{ hex, type }] (a Game's team units, or a parsed lineup), all
// one side, standing on the player's rows. Answers the enemy's first turns
// that take the king: [{ attacker, from, via, to }] (`via` is a cavalry unit's
// first-jump hex, or null), empty when the king is safe.
export function kingThreats(army) {
  const king = army.find((u) => u.type.codename === "king");
  if (!king) throw new Error("the army has no king");
  const own = new Map(army.map((u) => [u.hex, { team: "own", type: u.type }]));
  const threats = [];

  for (const codename of ATTACKERS) {
    const type = UNIT_TYPES[codename];
    for (const from of COMPUTER_ZONE) {
      const board = new Map(own);
      board.set(from, { team: ENEMY, type });
      const first = legalActions(position(board), from);
      if (first.attacks.includes(king.hex)) {
        threats.push({ attacker: codename, from, via: null, to: king.hex });
        continue;
      }
      if (type.rank !== "cavalry") continue;
      for (const via of [...first.moves, ...first.attacks]) {
        const after = new Map(board);
        after.delete(from);
        after.set(via, { team: ENEMY, type });
        const second = legalActions(position(after), via, { jump: 2 });
        if (second.attacks.includes(king.hex)) {
          threats.push({ attacker: codename, from, via, to: king.hex });
          break;
        }
      }
    }
  }
  return threats;
}

export function kingSafe(army) {
  return kingThreats(army).length === 0;
}

function position(board) {
  return { pieceAt: (hex) => board.get(hex) };
}
