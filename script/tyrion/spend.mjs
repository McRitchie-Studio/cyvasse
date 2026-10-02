// What Tyrion's chat may spend in a day (task tyrion-runner-safeguards).
//
// His turns are his own search (brain.mjs) and cost nothing; only his chat
// calls a paid model. The ChatBudget in voice.mjs caps what one player can
// make him say, but it lives in memory, so a restart forgets it. This ledger
// is the overall cap: model calls and their estimated dollars per UTC day,
// kept in a small JSON file that a restart reads back. Once either cap is
// reached he makes no more model calls until UTC midnight and answers from
// his stock lines, which cost nothing; he plays on as before.
//
//   TYRION_MAX_SPEND_USD     default 1.00 dollars a UTC day
//   TYRION_MAX_MODEL_CALLS   default 200 calls a UTC day
//   TYRION_SPEND_LEDGER      default tmp/tyrion-spend.json (bin/tyrion runs from the repo root)
//
// The dollars are an estimate from each response's token counts and the
// prices below, the one place they are kept. A model not listed is charged
// at the dearest row, so an unknown model reaches the cap sooner, not later.

import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export const DEFAULT_MAX_SPEND_USD = 1.0;
export const DEFAULT_MAX_MODEL_CALLS = 200;
export const DEFAULT_LEDGER_PATH = "tmp/tyrion-spend.json";

// Dollars per million tokens, first-party API list prices (input, output).
export const PRICES = Object.freeze({
  "claude-opus-5-5": { input: 4, output: 20 },
  "claude-opus-5": { input: 5, output: 25 },
  "claude-sonnet-5": { input: 2, output: 10 },
  "claude-haiku-4-5": { input: 1, output: 5 },
  "claude-fable-5-1": { input: 10, output: 50 }
});
const DEAREST = Object.values(PRICES).reduce((a, b) => (b.output > a.output ? b : a));

// The estimated dollars of one response's `usage`. Cache reads and writes are
// charged as plain input: an overestimate, which errs toward the cap.
export function costOf(model, usage = {}) {
  const price = PRICES[model] ?? DEAREST;
  const input = (usage.input_tokens ?? 0) + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0);
  const output = usage.output_tokens ?? 0;
  return (input * price.input + output * price.output) / 1_000_000;
}

export function utcDay(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

function positive(raw, fallback) {
  const n = Number(raw);
  return raw !== undefined && raw !== "" && Number.isFinite(n) && n >= 0 ? n : fallback;
}

export class SpendLedger {
  static fromEnv(env = process.env, options = {}) {
    return new SpendLedger({
      path: env.TYRION_SPEND_LEDGER || DEFAULT_LEDGER_PATH,
      maxUsd: positive(env.TYRION_MAX_SPEND_USD, DEFAULT_MAX_SPEND_USD),
      maxCalls: positive(env.TYRION_MAX_MODEL_CALLS, DEFAULT_MAX_MODEL_CALLS),
      ...options
    });
  }

  constructor({ path = DEFAULT_LEDGER_PATH, maxUsd = DEFAULT_MAX_SPEND_USD, maxCalls = DEFAULT_MAX_MODEL_CALLS, now = () => Date.now(), log = console } = {}) {
    this.path = path;
    this.maxUsd = maxUsd;
    this.maxCalls = maxCalls;
    this.now = now;
    this.log = log;
    this.entry = this.#load();
    this.warnedDay = null;
  }

  // Whether one more model call is allowed today. Logs once a day when not.
  allow() {
    const entry = this.#today();
    if (entry.calls < this.maxCalls && entry.usd < this.maxUsd) return true;
    if (this.warnedDay !== entry.day) {
      this.warnedDay = entry.day;
      this.log.warn(`tyrion: daily model cap reached (${entry.calls}/${this.maxCalls} calls, $${entry.usd.toFixed(4)}/$${this.maxUsd.toFixed(2)}); stock lines until UTC midnight`);
    }
    return false;
  }

  // Counts one model call and its estimated dollars, and writes the file.
  record(usd = 0) {
    const entry = this.#today();
    entry.calls += 1;
    entry.usd += Math.max(0, Number(usd) || 0);
    this.#save();
  }

  get today() {
    const { day, calls, usd } = this.#today();
    return { day, calls, usd };
  }

  #today() {
    const day = utcDay(this.now());
    if (this.entry.day !== day) this.entry = { day, calls: 0, usd: 0 };
    return this.entry;
  }

  // A ledger that cannot be read fails closed: today counts as spent, so a
  // damaged file can never reopen the purse. Writes are atomic (a rename), so
  // only a person damages it, and a person removes it. A missing one is a
  // fresh start.
  #load() {
    let raw;
    try {
      raw = readFileSync(this.path, "utf8");
    } catch (error) {
      if (error.code === "ENOENT") return { day: null, calls: 0, usd: 0 };
      this.log.warn(`tyrion: cannot read the spend ledger ${this.path} (${error.code}); no model calls until it can be read`);
      return this.#spent();
    }
    try {
      const parsed = JSON.parse(raw);
      if (typeof parsed.day !== "string" || !Number.isFinite(parsed.calls) || !Number.isFinite(parsed.usd)) throw new Error("shape");
      return { day: parsed.day, calls: parsed.calls, usd: parsed.usd };
    } catch {
      this.log.warn(`tyrion: the spend ledger ${this.path} is damaged; no model calls until it is fixed or removed`);
      return this.#spent();
    }
  }

  #spent() {
    return { day: utcDay(this.now()), calls: Infinity, usd: Infinity };
  }

  #save() {
    if (!Number.isFinite(this.entry.calls)) return; // a failed-closed day is never written over the damaged file
    try {
      mkdirSync(dirname(this.path), { recursive: true });
      const tmp = `${this.path}.${process.pid}.tmp`;
      writeFileSync(tmp, `${JSON.stringify(this.entry)}\n`);
      renameSync(tmp, this.path);
    } catch (error) {
      this.log.warn(`tyrion: cannot write the spend ledger (${error.code ?? error.message})`);
    }
  }
}
