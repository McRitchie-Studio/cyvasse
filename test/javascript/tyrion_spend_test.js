// [unit] Tyrion's daily model cap (script/tyrion/spend.mjs) and its wiring
// into the chat (chat.mjs) with a stand-in for the Anthropic SDK: the cap
// stops model calls, survives a restart, resets at UTC midnight, and fails
// closed on a damaged ledger.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { PRICES, SpendLedger, costOf, DEFAULT_MAX_MODEL_CALLS, DEFAULT_MAX_SPEND_USD } from "../../script/tyrion/spend.mjs";
import { makeChat } from "../../script/tyrion/chat.mjs";

const NOON = Date.parse("2026-10-01T12:00:00Z");
const quiet = () => {
  const warnings = [];
  return { warnings, info() {}, warn(m) { warnings.push(m); }, error(m) { warnings.push(m); } };
};
const ledgerPath = () => join(mkdtempSync(join(tmpdir(), "tyrion-spend-")), "nested", "spend.json");

// The SDK's shape as chat.mjs uses it: a default-exported class with
// beta.messages.create and the error classes it checks with instanceof.
function fakeSdk({ usage = { input_tokens: 1000, output_tokens: 500 }, fail = null } = {}) {
  const calls = [];
  class APIError extends Error {}
  class APIConnectionError extends APIError {}
  class RateLimitError extends APIError {}
  class Anthropic {
    constructor() {
      this.beta = { messages: { create: async (params) => {
        calls.push(params);
        if (fail) throw fail(Anthropic);
        return { stop_reason: "end_turn", usage, content: [{ type: "text", text: "Your move." }] };
      } } };
    }
  }
  Object.assign(Anthropic, { APIError, APIConnectionError, RateLimitError });
  return { Anthropic, calls };
}

test("costOf prices one response from its token counts, an unknown model at the dearest row", () => {
  assert.equal(costOf("claude-opus-5-5", { input_tokens: 1_000_000, output_tokens: 1_000_000 }), 24);
  assert.equal(costOf("claude-opus-5-5", { input_tokens: 500_000, cache_read_input_tokens: 500_000 }), 4, "cache reads charged as input");
  const dearest = Math.max(...Object.values(PRICES).map((p) => p.output));
  assert.equal(costOf("some-future-model", { output_tokens: 1_000_000 }), dearest);
  assert.equal(costOf("claude-opus-5-5", undefined), 0);
});

test("the defaults are conservative and env overrides them; nonsense falls back", () => {
  const path = ledgerPath();
  const dflt = SpendLedger.fromEnv({ TYRION_SPEND_LEDGER: path }, { log: quiet() });
  assert.equal(dflt.maxUsd, DEFAULT_MAX_SPEND_USD);
  assert.equal(dflt.maxCalls, DEFAULT_MAX_MODEL_CALLS);
  assert.ok(DEFAULT_MAX_SPEND_USD <= 1 && DEFAULT_MAX_MODEL_CALLS <= 200);
  const set = SpendLedger.fromEnv({ TYRION_SPEND_LEDGER: path, TYRION_MAX_SPEND_USD: "0.25", TYRION_MAX_MODEL_CALLS: "3" }, { log: quiet() });
  assert.equal(set.maxUsd, 0.25);
  assert.equal(set.maxCalls, 3);
  const junk = SpendLedger.fromEnv({ TYRION_SPEND_LEDGER: path, TYRION_MAX_SPEND_USD: "lots", TYRION_MAX_MODEL_CALLS: "-1" }, { log: quiet() });
  assert.equal(junk.maxUsd, DEFAULT_MAX_SPEND_USD);
  assert.equal(junk.maxCalls, DEFAULT_MAX_MODEL_CALLS);
});

test("the call cap blocks further model calls, and a restart remembers it", async () => {
  const path = ledgerPath();
  const log = quiet();
  const { Anthropic, calls } = fakeSdk();
  const ledger = new SpendLedger({ path, maxCalls: 2, maxUsd: 100, now: () => NOON, log });
  const chat = await makeChat({ apiKey: "sk-test", ledger, sdk: Anthropic, log });

  assert.equal(await chat.reply({ board: "b", chat: [] }), "Your move.");
  assert.equal(await chat.reply({ board: "b", chat: [] }), "Your move.");
  assert.equal(await chat.reply({ board: "b", chat: [] }), null, "past the cap: no line");
  assert.equal(calls.length, 2, "and no model call");
  assert.equal(log.warnings.filter((w) => /daily model cap reached/.test(w)).length, 1, "said once, clearly");
  assert.ok(!log.warnings.some((w) => w.includes("sk-test")), "no key in the log");

  const onDisk = JSON.parse(readFileSync(path, "utf8"));
  assert.deepEqual({ day: onDisk.day, calls: onDisk.calls }, { day: "2026-10-01", calls: 2 });

  // A restart: a new process reads the same file.
  const restarted = fakeSdk();
  const again = await makeChat({ apiKey: "sk-test", ledger: new SpendLedger({ path, maxCalls: 2, maxUsd: 100, now: () => NOON + 60_000, log: quiet() }), sdk: restarted.Anthropic, log: quiet() });
  assert.equal(await again.reply({ board: "b", chat: [] }), null);
  assert.equal(restarted.calls.length, 0, "the restart did not reopen the purse");
});

test("the dollar cap blocks once the estimated spend reaches it, across a restart", async () => {
  const path = ledgerPath();
  // 1,000 in + 500 out on Opus 5.5 = $0.014 a call; a $0.03 cap allows three.
  const { Anthropic, calls } = fakeSdk();
  const make = (now) => makeChat({ apiKey: "sk-test", model: "claude-opus-5-5", ledger: new SpendLedger({ path, maxCalls: 1000, maxUsd: 0.03, now: () => now, log: quiet() }), sdk: Anthropic, log: quiet() });
  const first = await make(NOON);
  await first.reply({ board: "b", chat: [] });
  await first.reply({ board: "b", chat: [] });
  const second = await make(NOON + 1000); // restart mid-day
  assert.equal(await second.reply({ board: "b", chat: [] }), "Your move.", "$0.028 spent, under $0.03");
  assert.equal(await second.reply({ board: "b", chat: [] }), null, "$0.042 spent: blocked");
  assert.equal(calls.length, 3);
  const onDisk = JSON.parse(readFileSync(path, "utf8"));
  assert.ok(Math.abs(onDisk.usd - 0.042) < 1e-9, `ledger holds the estimate (${onDisk.usd})`);
});

test("a failed model call still counts toward the day's calls", async () => {
  const { Anthropic, calls } = fakeSdk({ fail: (sdk) => new sdk.RateLimitError("429") });
  const ledger = new SpendLedger({ path: ledgerPath(), maxCalls: 1, maxUsd: 100, now: () => NOON, log: quiet() });
  const chat = await makeChat({ apiKey: "sk-test", ledger, sdk: Anthropic, log: quiet() });
  assert.equal(await chat.reply({ board: "b", chat: [] }), null);
  assert.equal(ledger.today.calls, 1);
  assert.equal(await chat.reply({ board: "b", chat: [] }), null);
  assert.equal(calls.length, 1, "the second was never sent");
});

test("the cap resets at UTC midnight", () => {
  const path = ledgerPath();
  let now = Date.parse("2026-10-01T23:59:00Z");
  const ledger = new SpendLedger({ path, maxCalls: 1, maxUsd: 100, now: () => now, log: quiet() });
  assert.equal(ledger.allow(), true);
  ledger.record(0.01);
  assert.equal(ledger.allow(), false);
  now = Date.parse("2026-10-02T00:00:01Z");
  const restarted = new SpendLedger({ path, maxCalls: 1, maxUsd: 100, now: () => now, log: quiet() });
  assert.equal(restarted.allow(), true, "a new UTC day");
  assert.deepEqual(restarted.today, { day: "2026-10-02", calls: 0, usd: 0 });
});

test("a damaged ledger fails closed until a person removes it, and is not written over", () => {
  const path = join(mkdtempSync(join(tmpdir(), "tyrion-spend-")), "spend.json");
  writeFileSync(path, "{not json");
  const log = quiet();
  const ledger = new SpendLedger({ path, now: () => NOON, log });
  assert.equal(ledger.allow(), false);
  assert.ok(log.warnings.some((w) => /damaged/.test(w)));
  assert.equal(readFileSync(path, "utf8"), "{not json", "left for a person to look at");
  const tomorrow = new SpendLedger({ path, now: () => NOON + 86_400_000, log: quiet() });
  assert.equal(tomorrow.allow(), false, "still closed the next day: the file is still damaged");
  rmSync(path);
  const removed = new SpendLedger({ path, now: () => NOON + 86_400_000, log: quiet() });
  assert.equal(removed.allow(), true, "removed, it starts fresh");
});

test("makeChat refuses to build a chat with no ledger", async () => {
  const { Anthropic } = fakeSdk();
  await assert.rejects(makeChat({ apiKey: "sk-test", sdk: Anthropic, log: quiet() }), /spend ledger/);
  assert.equal(await makeChat({ apiKey: "", log: quiet() }), null, "no key, no chat, no ledger needed");
});
