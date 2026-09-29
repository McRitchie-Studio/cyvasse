// The setup panel's "✨ Smart Setup" button: it places one of the strategic
// openings (cyvasse/openings), never one of the player's last ten picks.
//
// The pool is every opening that keeps its king out of a first-turn dragon
// strike (all but the King's Gambit) and opens with both elephants on the
// front row, where their short move still reaches the enemy.
//
// With part of the army already placed ("✨ Place All") the placed units stay
// where they are: the opening that fits them best places the rest, and a unit
// whose hex is taken goes to the free hex nearest the one it wanted.

import { OPENINGS, openingLineup } from "cyvasse/openings";
import { parseLineup, formatLineup } from "cyvasse/setups";
import { hexAt, PLAYER_ZONE } from "cyvasse/board";
import { KILL_PRIORITY } from "cyvasse/ai";

export const RECENT_WINDOW = 10;
export const RECENT_KEY = "cyvasse.smartSetups";

export const SMART_SETUPS = Object.freeze(
  OPENINGS.filter((o) => o.slug !== "kings-gambit" && [...o.rows[0]].filter((c) => c === "E").length === 2)
);

// The three faces of the button, by how much of the army is on the board.
export function smartSetupMode(placed, total) {
  if (placed === 0) return "smart";
  return placed < total ? "fill" : "new";
}

export const SMART_LABELS = Object.freeze({ smart: "✨ Smart Setup", fill: "✨ Place All", new: "✨ New Setup" });

// The player's army ([{ index, type: { codename }, hex, status }]) as a whole
// lineup string. Answers { opening, lineup }.
export function smartLineup(units, { recent = [], rng = Math.random } = {}) {
  const placed = units.filter((u) => u.status === "alive");
  const candidates = eligible(recent);
  if (placed.length === 0 || placed.length === units.length) {
    const opening = candidates[Math.floor(rng() * candidates.length)];
    return { opening, lineup: openingLineup(opening) };
  }
  // Fewest units pushed off their hex, then most placed units already on one.
  const score = ({ displaced, kept }) => displaced * units.length - kept;
  let best = [];
  let lowest = Infinity;
  for (const opening of candidates) {
    const plan = completeAround(units, opening);
    if (score(plan) < lowest) {
      lowest = score(plan);
      best = [];
    }
    if (score(plan) === lowest) best.push({ opening, lineup: plan.lineup });
  }
  return best[Math.floor(rng() * best.length)];
}

// The openings not among the last RECENT_WINDOW picks (oldest first).
export function eligible(recent) {
  const skip = new Set(recent.slice(-RECENT_WINDOW));
  const left = SMART_SETUPS.filter((o) => !skip.has(o.slug));
  return left.length > 0 ? left : SMART_SETUPS.filter((o) => o.slug !== recent[recent.length - 1]);
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
