// Twenty-five opening lineups for the setup panel, each one idea on the board.
//
// A lineup is drawn as the player's five rows, front (row 7, beside no man's
// land) to back (row 11), ten hexes across down to six, one letter a hex:
//
//   K king      D dragon     E elephant    T trebuchet   C catapult
//   X crossbow  H heavy horse  L light horse  S spearman  R rabble
//   M mountain  . empty
//
// The rows are centred on the board, so a hex in row n sits between two in
// the row above it: the one at the same position and the one after it. From
// a unit at position j, the diagonal up and to the left keeps j in every row
// above; the diagonal up and to the right adds one per row.
//
// Two rules shape most of them (cyvasse/rules.js, cyvasse/game.js):
//   - The enemy dragon flies any distance in a straight line, over mountains
//     and most units, and can take the king from across the board. An enemy
//     trebuchet, catapult, crossbow or dragon makes it stop: it can take any
//     of them, but its flight ends there (since the offense-only trumps of
//     September 29, 2026 the trebuchet and catapult no longer repel it). A
//     king whose two forward diagonals each meet one of those four first is
//     safe from a first-turn dragon strike.
//   - The side whose king stands nearer the middle row moves first.
//
// openingLineup(opening) turns a drawing into the legacy setup string that
// Game#loadLineup and the saved-lineup panel already speak.

import { ARMY } from "cyvasse/units";
import { hexAtXY } from "cyvasse/board";
import { formatLineup } from "cyvasse/setups";

export const LETTERS = Object.freeze({
  K: "king", D: "dragon", E: "elephant", T: "trebuchet", C: "catapult", X: "crossbowman",
  H: "heavyhorse", L: "lighthorse", S: "spearman", R: "rabble", M: "mountain"
});

export const OPENINGS = Object.freeze([
  opening("iron-corner", "Iron Corner",
    "The king takes the back corner behind a crossbow, a catapult and a crossbow, so no dragon can reach it; the trebuchet on the same long diagonal doubles the seal. Slow and safe.",
    ["M.ESTSE.M.", "L.H.D.H.L", "R..R..R.", "XC.....", "KX...."]),
  opening("dragons-lair", "Dragon's Lair",
    "The king sits in the middle of the back row between two crossbows, with the catapult and your own dragon on its diagonals. The dragon launches from beside the throne.",
    ["L.SETE.S.L", ".H.R.R.H.", "..M..M.R", "..CD...", ".XKX.."]),
  opening("kings-gambit", "King's Gambit",
    "The king stands on the front row, so you move first unless their king is on the front row too. Elephants flank it and the trebuchet and catapult stand right behind, but its forward diagonals are open: spend the first move reading their dragon.",
    ["..SEKES...", "L.HTC.H.L", "X..D...X", "R.M.M.R", "..R..."]),
  opening("crown-forward", "Crown Forward",
    "The king stands two rows up, near enough the middle to move first against every computer army, with the trebuchet and catapult on its two forward diagonals.",
    ["L.SETCES.L", "M.H.K.H.M", ".X.D..X.", "R..R..R", "......"]),
  opening("open-skies", "Open Skies",
    "Your dragon opens on the front row with its lines running into their camp. The catapult and trebuchet sit on your king's diagonals, so their dragon cannot answer in kind.",
    ["LE.S.D.SEL", "H..CT..H.", "X..K...X", "RM.R.MR", "......"]),
  opening("mountain-pass", "Mountain Pass",
    "Two mountains wall the front with a two-hex gap between them. Spearmen and heavy horse guard the gap and the trebuchet waits right behind it.",
    ["L.EM..ME.L", "..SHTHS..", ".X.CD.X.", "R..K..R", "..R..."]),
  opening("horse-lords", "Horse Lords",
    "All four horses start on the front row, ready to jump twice into their lines on the first turn, with the elephants holding the centre between them.",
    ["LH..EE..HL", "..S.T.S..", "M..CX..M", "R.XKD.R", "..R..."]),
  opening("grey-wall", "Grey Wall",
    "Elephants and spearmen make the front line with mountains on the wings. Only a dragon, a spearman or another elephant can take an elephant, and your spearmen stand right beside yours to punish the enemy's.",
    ["M.SE..ES.M", ".X.T.C.X.", "L.HD.H.L", "..RKR..", "..R..."]),
  opening("siege-line", "Siege Line",
    "The trebuchet, the catapult and both crossbows open on the front row around a pair of elephants. Shooters fire without moving, and from there they reach the enemy's front rows.",
    ["..XTEECX..", "S.L...L.S", ".H.MM.H.", "R.DK.R.", "...R.."]),
  opening("left-hook", "Left Hook",
    "Horses, an elephant and the dragon mass on the left for one heavy blow while the mountains and shooters hold the right, where the king waits behind a crossbow and the catapult.",
    ["LHED.S..M.", "LHE.T..SM", "R.R..XC.", ".R..XK.", "......"]),
  opening("hammer-and-anvil", "Hammer and Anvil",
    "Elephants and spearmen are the anvil in the centre; light and heavy horse on both wings are the hammer that swings round to pin the enemy against it.",
    ["L..SEES..L", "H..T.C..H", "..X.DX..", "M..K..M", ".R.R.R"]),
  opening("rabble-screen", "Rabble Screen",
    "Three rabble lead the way as bait. The computer takes whatever it can; whatever steps up to take them lands next to the elephants, the trebuchet and the crossbows.",
    [".R..R...R.", ".X.ETE.X.", "L.SCD.SL", "H.MK.MH", "......"]),
  opening("spear-hedge", "Spear Hedge",
    "Spearmen hold both wings, where light horse like to raid: a spearman takes a light horse, and a light horse cannot take a spearman. The king waits in the centre behind the catapult.",
    ["S.E...TE.S", ".R.RC.R..", "L..XKX.L", "H.M.M.H", "..D..."]),
  opening("crossbow-ambush", "Crossbow Ambush",
    "Spearmen and mountains lead, and the crossbows hide in the second row to shoot whatever comes through. An enemy elephant that breaks through meets a spearman, which trumps it and takes it whatever the strengths.",
    ["L.S.MM.S.L", "..X.T.X..", ".HECDEH.", "R..K..R", "..R..."]),
  opening("the-keep", "The Keep",
    "The king stands in the middle of the fourth row, flanked by elephants, with the catapult and your dragon above it. The trebuchet fires from between the two front mountains.",
    ["L.HMTM.H.L", ".R.S.S.R.", "..XCDX..", "..EKE..", "..R..."]),
  opening("dragon-hunt", "Dragon Hunt",
    "Trebuchet, crossbows and catapult sit together in the centre of the front row. Their dragon must stop at the first of them it takes, and the trebuchet and catapult both trump it, so either one can take it back.",
    ["E..TXXC..E", "L.S...S.L", ".H.MM.H.", "R.RKD.R", "......"]),
  opening("shadow-keep", "Shadow Keep",
    "Two mountains stand directly in front of the king: nothing on foot walks through them and no shot passes through them. The trebuchet and catapult beyond them, on the same diagonals, stop the dragon.",
    ["L.E.T.C.EL", "H.S.MM.SH", ".X.RK.X.", "R.D...R", "......"]),
  opening("centre-column", "Centre Column",
    "Everything stacks down the middle and mountains close the wings. The enemy has to come through the centre, straight into the elephants, horses and dragon.",
    ["M..HEEH..M", "...STS...", "..LDCL..", "..XKX..", ".RRR.."]),
  opening("wide-net", "Wide Net",
    "Nine units cover the front row from edge to edge, so nothing crosses no man's land without a fight. The catapult and a crossbow guard the king's diagonals from the second row.",
    ["LSHE.TEHSL", "..XCX.D..", "M..K...M", ".R.R.R.", "......"]),
  opening("the-split", "The Split",
    "Both mountains stand in the centre of the front row and split their advance in two. Each half meets its own elephant and horse, while the dragon and catapult shield the king.",
    ["LE..MM..EL", ".HS.T.SH.", "X..CD..X", "R..K..R", "..R..."]),
  opening("tusk-line", "Tusk Line",
    "Both elephants stand on the front row with a spearman and a light horse beside each. The king waits in the back row with the catapult and trebuchet directly above it.",
    ["LE.S..SE.L", ".H..D..H.", "M.X..X.M", "..RCTR.", "R..K.."]),
  opening("wall-of-tusks", "Wall of Tusks",
    "The elephants stand shoulder to shoulder in the centre of the front row, spearmen and mountains beside them. Your dragon and the catapult sit on the king's diagonals.",
    ["M.S.EE.S.M", "L.H.T.H.L", "..XDCX..", "R..K..R", "..R..."]),
  opening("rams-head", "Ram's Head",
    "Each elephant leads from the front row with a heavy horse on its outside and the light horse between them. The king stands under a crossbow and the catapult.",
    ["HE..LL..EH", ".S..T..S.", "M.XC.X.M", "R.K.D.R", "..R..."]),
  opening("front-guard", "Front Guard",
    "Spearmen, elephants and both crossbows hold the front row together, so anything that steps up to them meets a shooter. The trebuchet and catapult cover the king.",
    ["S.EX..XE.S", "L..H.H..L", "M..TC..M", "R..K..R", "..RD.."]),
  opening("wide-tusks", "Wide Tusks",
    "The elephants hold the two ends of the front row, facing down each flank, with the spearmen in the centre. The catapult and trebuchet stand above the king.",
    ["E.L.SS.L.E", ".H.X.X.H.", "M..CT..M", ".R.K.R.", "..D.R."])
]);

// The opening's legacy setup string ("unitIndex:hex|", from the player's
// seat), each letter given the next unused army index of its type.
export function openingLineup({ rows }) {
  const nextIndex = new Map();
  const pairs = [];
  rows.forEach((row, r) => {
    [...row].forEach((letter, j) => {
      if (letter === ".") return;
      const codename = LETTERS[letter];
      if (!codename) throw new Error(`unknown letter ${letter}`);
      const index = ARMY.indexOf(codename, nextIndex.get(codename) ?? 0);
      if (index === -1) throw new Error(`too many ${codename}`);
      nextIndex.set(codename, index + 1);
      const hex = hexAtXY(j + 1, r + 7);
      if (!hex) throw new Error(`row ${r + 7} has no hex ${j + 1}`);
      pairs.push([index + 1, hex.index]);
    });
  });
  return formatLineup(pairs.sort((a, b) => a[0] - b[0]));
}

function opening(slug, name, idea, rows) {
  return Object.freeze({ slug, name, idea, rows: Object.freeze(rows) });
}
