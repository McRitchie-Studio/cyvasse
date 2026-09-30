// The setup panel's "✨ Smart Setup" button: it places one of the strategic
// openings (cyvasse/openings), never one of the player's last ten picks.
//
// The pool is every opening whose king survives the enemy's first turn,
// whatever the enemy placed and played (cyvasse/king_safety: a light horse
// raid, a dragon flight, a shot), and that opens with both elephants on the
// front row, where their short move still reaches the enemy. The King's
// Gambit and Crown Forward, whose kings stand forward on purpose, stay out.
//
// With part of the army already placed ("✨ Place All") the placed units stay
// where they are: of the fills the openings offer, one whose king is safe
// wins; among those, the one that fits the placed units best.

import { OPENINGS, openingLineup } from "cyvasse/openings";
import { parseLineup, formatLineup } from "cyvasse/setups";
import { distance, hexAt, neighbors, PLAYER_ZONE } from "cyvasse/board";
import { KILL_PRIORITY } from "cyvasse/ai";
import { kingThreats, kingSafe } from "cyvasse/king_safety";
import { typeAt } from "cyvasse/units";

export const RECENT_WINDOW = 10;
export const RECENT_KEY = "cyvasse.smartSetups";

// The pool, worked out on first use: the check walks every enemy unit on
// every enemy hex, a few milliseconds an opening, so a page that never opens
// the setup panel never pays for it.
let pool = null;
export function smartSetups() {
  pool ??= Object.freeze(OPENINGS.filter((o) => elephantsInFront(o) && kingSafe(armyOf(openingLineup(o)))));
  return pool;
}

function elephantsInFront({ rows }) {
  return [...rows[0]].filter((c) => c === "E").length === 2;
}

// A lineup string as the [{ hex, type }] army cyvasse/king_safety reads.
export function armyOf(lineup) {
  return parseLineup(lineup).map(([index, hex]) => ({ hex, type: typeAt(index) }));
}

// The three faces of the button, by how much of the army is on the board.
export function smartSetupMode(placed, total) {
  if (placed === 0) return "smart";
  return placed < total ? "fill" : "new";
}

// The words only: the button's ✨ is decoration (games/_army_card), hidden
// from screen readers, so the button reads "Smart Setup", not "sparkles".
export const SMART_LABELS = Object.freeze({ smart: "Smart Setup", fill: "Place All", new: "New Setup" });

// The player's army ([{ index, type: { codename }, hex, status }]) as a whole
// lineup string. Answers { opening, lineup }.
export function smartLineup(units, { recent = [], rng = Math.random } = {}) {
  const placed = units.filter((u) => u.status === "alive");
  const candidates = eligible(recent);
  if (placed.length === 0 || placed.length === units.length) {
    const opening = candidates[Math.floor(rng() * candidates.length)];
    return { opening, lineup: openingLineup(opening) };
  }
  // The fewest ways to lose the king on the enemy's first turn (none, when
  // any fill allows it), then the fewest units pushed off their hex, then the
  // most placed units already on one. The recent picks are skipped only
  // while that costs no safety: every opening is tried.
  const score = ({ displaced, kept }) => displaced * units.length - kept;
  const plans = new Map();
  for (const opening of smartSetups()) {
    const plan = completeAround(units, opening);
    plans.set(opening, plan);
  }
  const ranked = [...plans].map(([opening, plan]) => ({ opening, plan, fresh: candidates.includes(opening) }));
  const safe = ranked.filter(({ plan }) => kingSafe(armyOf(plan.lineup)));
  let pickFrom;
  if (safe.length > 0) {
    pickFrom = safe.some((r) => r.fresh) ? safe.filter((r) => r.fresh) : safe;
  } else {
    // Counted only as far as the fewest so far: a worse fill stops early.
    let fewest = Infinity;
    const threats = new Map();
    for (const r of ranked) {
      const n = kingThreats(armyOf(r.plan.lineup), { limit: fewest + 1 }).length;
      threats.set(r, n);
      fewest = Math.min(fewest, n);
    }
    pickFrom = ranked.filter((r) => threats.get(r) === fewest);
  }
  const lowest = Math.min(...pickFrom.map(({ plan }) => score(plan)));
  const best = pickFrom.filter(({ plan }) => score(plan) === lowest);
  const { opening, plan } = best[Math.floor(rng() * best.length)];
  return { opening, lineup: safe.length > 0 ? plan.lineup : secure(units, plan.lineup) };
}

// When no opening's fill keeps the king safe, rearrange the units Place All
// placed (never the player's own) until it is, or until nothing more helps.
// A change stands the king (if Place All placed it) on another hex, or puts
// a placed unit next to the king, on the hex a raider lands on first, or in
// the path of a flight or a shot. Each step keeps the change that leaves the
// fewest ways in; when no single change helps, a king move followed by one
// more change is tried, since the king's new hex may need its own guard.
export function secure(units, lineup, { budget } = {}) {
  const fixed = new Set(units.filter((u) => u.status === "alive").map((u) => u.index));
  const at = new Map(parseLineup(lineup));
  const kingIndex = [...at.keys()].find((index) => typeAt(index).codename === "king");
  // A king the player stood forward is usually past saving, and every look
  // at it is dear: it gets a fifth of the looks a king still in the dock gets.
  budget ??= fixed.has(kingIndex) ? 300 : 1500;
  // Each look is a few milliseconds; the budget keeps one click to about a
  // second however hopeless the player's own placements are.
  let looks = 0;
  const threats = (limit = Infinity) => {
    looks += 1;
    return kingThreats([...at].map(([index, hex]) => ({ hex, type: typeAt(index) })), { limit });
  };

  // Move unit `index` to `hex`, swapping with a Place All unit standing
  // there; answers the undo.
  const move = (index, hex) => {
    const other = [...at].find(([, h]) => h === hex)?.[0];
    const from = at.get(index);
    at.set(index, hex);
    if (other !== undefined) at.set(other, from);
    return () => {
      at.set(index, from);
      if (other !== undefined) at.set(other, hex);
    };
  };
  const guardMoves = (current) => {
    const kingHex = at.get(kingIndex);
    const hot = new Set(neighbours(kingHex));
    for (const { from, via } of current) {
      if (via != null) hot.add(via);
      else for (const hex of between(from, kingHex)) hot.add(hex);
    }
    const holder = new Map([...at].map(([index, hex]) => [hex, index]));
    const out = [];
    for (const hex of hot) {
      if (!PLAYER_ZONE.includes(hex) || fixed.has(holder.get(hex))) continue;
      for (const index of at.keys()) if (!fixed.has(index) && index !== kingIndex && at.get(index) !== hex) out.push([index, hex]);
    }
    return out;
  };
  const kingMoves = () => {
    if (fixed.has(kingIndex)) return [];
    const taken = new Set(units.filter((u) => u.status === "alive").map((u) => u.hex));
    return PLAYER_ZONE.filter((hex) => hex !== at.get(kingIndex) && !taken.has(hex)).map((hex) => [kingIndex, hex]);
  };
  // The one change among `tries` that leaves fewer than `bound` ways in.
  const bestOf = (tries, bound) => {
    let best = null;
    let fewest = bound;
    for (const [index, hex] of tries) {
      if (looks > budget) break;
      const undo = move(index, hex);
      const n = threats(fewest).length;
      undo();
      if (n < fewest) [best, fewest] = [[index, hex], n];
      if (fewest === 0) break;
    }
    return best && { change: best, left: fewest };
  };

  let current = threats();
  while (current.length > 0 && looks <= budget) {
    const single = bestOf([...kingMoves(), ...guardMoves(current)], current.length);
    if (single) {
      move(...single.change);
      current = threats();
      continue;
    }
    let pair = null;
    for (const [index, hex] of kingMoves()) {
      if (looks > budget) break;
      const undo = move(index, hex);
      const after = threats();
      const next = after.length > 0 && bestOf(guardMoves(after), current.length);
      undo();
      if (next) {
        pair = [[index, hex], next.change];
        break;
      }
    }
    if (!pair) break;
    for (const change of pair) move(...change);
    current = threats();
  }
  return formatLineup([...at].sort((a, b) => a[0] - b[0]));
}

// The hexes on a shortest path from one hex to another (a flight or a
// shot runs along one).
function between(from, to) {
  const [a, b] = [hexAt(from), hexAt(to)];
  const span = distance(a, b);
  return PLAYER_ZONE.filter((hex) => hex !== to && distance(a, hexAt(hex)) + distance(hexAt(hex), b) === span);
}

function neighbours(hex) {
  return neighbors(hexAt(hex)).map((n) => n.index);
}

// The openings not among the last RECENT_WINDOW picks (oldest first).
export function eligible(recent) {
  const setups = smartSetups();
  const skip = new Set(recent.slice(-RECENT_WINDOW));
  const left = setups.filter((o) => !skip.has(o.slug));
  return left.length > 0 ? left : setups.filter((o) => o.slug !== recent[recent.length - 1]);
}

// Keep the placed units, place the rest by the opening. `displaced` counts
// the units that could not have their opening hex; `kept`, the placed units
// already standing where the opening puts a unit of their kind.
export function completeAround(units, opening) {
  const plan = new Map();
  for (const [index, hex] of parseLineup(openingLineup(opening))) {
    const codename = units.find((u) => u.index === index).type.codename;
    if (!plan.has(codename)) plan.set(codename, []);
    plan.get(codename).push(hex);
  }
  const taken = new Set();
  const pairs = [];
  let kept = 0;
  for (const unit of units.filter((u) => u.status === "alive")) {
    taken.add(unit.hex);
    pairs.push([unit.index, unit.hex]);
    const wants = plan.get(unit.type.codename);
    if (wants.includes(unit.hex)) {
      wants.splice(wants.indexOf(unit.hex), 1);
      kept += 1;
    }
  }
  const worth = (u) => -KILL_PRIORITY.indexOf(u.type.codename);
  const unplaced = units.filter((u) => u.status !== "alive").sort((a, b) => worth(a) - worth(b));
  const homeless = [];
  for (const unit of unplaced) {
    const wants = plan.get(unit.type.codename);
    const free = wants.find((hex) => !taken.has(hex));
    if (free === undefined) {
      homeless.push([unit, wants.shift()]);
      continue;
    }
    wants.splice(wants.indexOf(free), 1);
    taken.add(free);
    pairs.push([unit.index, free]);
  }
  for (const [unit, anchor] of homeless) {
    const hex = nearestFree(anchor, taken);
    taken.add(hex);
    pairs.push([unit.index, hex]);
  }
  return { lineup: formatLineup(pairs.sort((a, b) => a[0] - b[0])), displaced: homeless.length, kept };
}

function nearestFree(anchor, taken) {
  const from = centre(anchor);
  let best = null;
  let bestDistance = Infinity;
  for (const hex of PLAYER_ZONE) {
    if (taken.has(hex)) continue;
    const to = centre(hex);
    const distance = Math.hypot(to.x - from.x, to.y - from.y);
    if (distance < bestDistance) {
      best = hex;
      bestDistance = distance;
    }
  }
  return best;
}

// Rows are centred, so each row down from the middle starts half a hex in.
function centre(index) {
  const { x, y } = hexAt(index);
  return { x: x + Math.abs(y - 6) / 2, y: (y * Math.sqrt(3)) / 2 };
}

// The picks this browser remembers, oldest first. Storage may be refused.
export function recentPicks(storage = globalThis.localStorage) {
  try {
    const list = JSON.parse(storage?.getItem(RECENT_KEY) ?? "[]");
    return Array.isArray(list) ? list.filter((slug) => typeof slug === "string") : [];
  } catch {
    return [];
  }
}

// The list with `slug` as the newest pick, written back to storage.
export function rememberPick(recent, slug, storage = globalThis.localStorage) {
  const list = [...recent.filter((s) => s !== slug), slug].slice(-RECENT_WINDOW);
  try {
    storage?.setItem(RECENT_KEY, JSON.stringify(list));
  } catch {
    // A private window: the caller's list still covers this visit.
  }
  return list;
}
