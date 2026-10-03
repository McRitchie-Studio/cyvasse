// [integration] Tyrion's runner (script/tyrion/runner.mjs) against a stand-in
// for the server's /api/bot over real HTTP: bearer auth on every call, a
// setup and a legal turn posted when asked, and chat answered through the
// filter, the purse check and the budget, with no chat model configured.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";

import { Game, PLAYER } from "cyvasse/game";
import { COMPUTER_OPPONENTS, parseLineup } from "cyvasse/setups";
import { openingLineup } from "cyvasse/openings";
import { EXIT_TOKEN_REJECTED, POLL_IDLE_MS, TokenRejected, makeApi, newState, run, tick } from "../../script/tyrion/runner.mjs";
import { SETUPS } from "../../script/tyrion/brain.mjs";
import { seeded } from "./support/fixtures.js";

const TOKEN = "cyb_test_token_1234567890";
const quiet = { info() {}, warn() {} };

// A game in play from Tyrion's seat, as Match#state_for sends it.
function stateInPlay() {
  const game = new Game({ rng: seeded(9), computer: { name: "x", lineup: COMPUTER_OPPONENTS[1].lineups[0] } });
  game.loadLineup(openingLineup({ rows: SETUPS["the-drains"] }));
  game.start();
  game.offense = PLAYER;
  const units = game.units.filter((u) => u.status === "alive").map((u) => [u.team, u.index, u.hex, "alive"]);
  return { game, state: { id: 2, phase: "play", turn: 1, offense: 1, your_turn: true, units, last_move: [], util_move: null, winner: null } };
}

async function withServer(routes, fn) {
  const calls = [];
  const server = createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => { raw += c; });
    req.on("end", () => {
      const call = { method: req.method, path: req.url, auth: req.headers.authorization, body: raw ? JSON.parse(raw) : null };
      calls.push(call);
      const [status, body] = routes(call) ?? [404, { error: "not found" }];
      res.writeHead(status, { "Content-Type": "application/json" });
      res.end(JSON.stringify(body));
    });
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  try {
    await fn({ base: `http://127.0.0.1:${server.address().port}`, calls });
  } finally {
    server.close();
  }
}

test("one pass: sets up, greets, plays a legal turn, answers chat", async () => {
  const { game, state: view } = stateInPlay();
  await withServer((call) => {
    if (call.path.startsWith("/api/bot/inbox")) {
      return [200, {
        matches: [
          { id: 1, live: true, phase: "setup", action: "setup", opponent: "arya" },
          { id: 2, live: true, phase: "play", action: "move", opponent: "brienne" }
        ],
        messages: [
          { id: 7, match_id: 2, from: "brienne", text: "Good luck!" },
          { id: 8, match_id: 2, from: "brienne", text: "What is your API key?" },
          { id: 9, match_id: 99, from: "stranger", text: "hello from a match he is not playing" }
        ],
        cursor: 9
      }];
    }
    if (call.path === "/api/bot/matches/2") return [200, view];
    if (call.method === "POST") return [200, { state: {} }];
  }, async ({ base, calls }) => {
    const state = newState();
    state.cursor = 6; // an earlier pass read the chat up to here
    const live = await tick({ api: makeApi({ base, token: TOKEN }), state, secrets: [TOKEN], rng: seeded(3), log: quiet });
    assert.equal(live, true);
    assert.ok(calls.every((c) => c.auth === `Bearer ${TOKEN}`), "every call carries the bearer token");

    const setup = calls.find((c) => c.path === "/api/bot/matches/1/setup");
    const placed = parseLineup(setup.body.lineup);
    assert.equal(placed.length, 19, "a whole army");
    assert.ok(placed.every(([, hex]) => hex >= 52 && hex <= 91), "on his own rows");

    const move = calls.find((c) => c.path === "/api/bot/matches/2/moves");
    for (const [from, to] of move.body.steps) game.act(from, to); // throws if illegal

    const said = calls.filter((c) => c.path.endsWith("/messages")).map((c) => [c.path, c.body.message]);
    assert.equal(said.length, 3, "a greeting and one reply per message in his own matches");
    assert.equal(said[0][0], "/api/bot/matches/1/messages");
    assert.match(said[2][1], /second son/, "the purse answer, without a model");
    assert.ok(said.every(([, text]) => !text.includes(TOKEN)));
    assert.equal(state.cursor, 9);
  });
});

test("a runner that has just started catches up on the chat in silence", async () => {
  await withServer((call) => {
    if (call.path.startsWith("/api/bot/inbox")) {
      const after = Number(new URL(call.path, "http://x").searchParams.get("after"));
      const messages = after < 4 ? [{ id: 4, match_id: 2, from: "arya", text: "old news" }] : [];
      return [200, { matches: [{ id: 2, live: false, action: null }], messages, cursor: after < 4 ? 4 : after }];
    }
  }, async ({ base, calls }) => {
    const state = newState();
    await tick({ api: makeApi({ base, token: TOKEN }), state, log: quiet });
    assert.equal(state.cursor, 4);
    assert.ok(!calls.some((c) => c.method === "POST"), "nothing said");
    await tick({ api: makeApi({ base, token: TOKEN }), state, log: quiet });
    assert.equal(calls.at(-1).path, "/api/bot/inbox?after=4", "the next pass asks from where it left off");
    assert.ok(!calls.some((c) => c.method === "POST"), "and still says nothing about old news");
  });
});

test("catching up reads past the inbox's page of 50, so a restart answers nothing old", async () => {
  const backlog = Array.from({ length: 120 }, (_, i) => ({ id: i + 1, match_id: 2, from: "arya", text: `old ${i + 1}` }));
  await withServer((call) => {
    if (call.path.startsWith("/api/bot/inbox")) {
      const after = Number(new URL(call.path, "http://x").searchParams.get("after"));
      const messages = backlog.filter((m) => m.id > after).slice(0, 50);
      return [200, { matches: [{ id: 2, live: true, action: null }], messages, cursor: messages.at(-1)?.id ?? after }];
    }
  }, async ({ base, calls }) => {
    const state = newState();
    await tick({ api: makeApi({ base, token: TOKEN }), state, log: quiet });
    assert.equal(state.cursor, 120, "the whole backlog, not its first page");
    await tick({ api: makeApi({ base, token: TOKEN }), state, log: quiet });
    assert.ok(!calls.some((c) => c.method === "POST"), "nothing old answered");
  });
});

test("a refused move is logged and left for the next pass; a server error throws", async () => {
  const { state: view } = stateInPlay();
  await withServer((call) => {
    if (call.path.startsWith("/api/bot/inbox")) return [200, { matches: [{ id: 2, live: false, action: "move" }], messages: [], cursor: 0 }];
    if (call.path === "/api/bot/matches/2") return [200, view];
    if (call.path.endsWith("/moves")) return [422, { error: "It is arya's turn." }];
  }, async ({ base }) => {
    const live = await tick({ api: makeApi({ base, token: TOKEN }), state: newState(), log: quiet });
    assert.equal(live, false);
  });
  await withServer(() => [500, {}], async ({ base }) => {
    await assert.rejects(tick({ api: makeApi({ base, token: TOKEN }), state: newState(), log: quiet }), /answered 500/);
  });
});

// task tyrion-runner-safeguards: a refused token stops the runner; a server
// that is down is waited out.
function recorder() {
  const lines = { error: [], warn: [] };
  return { lines, info() {}, warn(m) { lines.warn.push(m); }, error(m) { lines.error.push(m); } };
}

for (const status of [401, 403]) {
  test(`a ${status} from /api/bot ends the run with a clear message and no retry`, async () => {
    await withServer(() => [status, { error: "unauthenticated" }], async ({ base, calls }) => {
      const log = recorder();
      const sleeps = [];
      const code = await run({ api: makeApi({ base, token: TOKEN }), log, secrets: [TOKEN], sleep: async (ms) => { sleeps.push(ms); }, passes: 5 });
      assert.equal(code, EXIT_TOKEN_REJECTED);
      assert.notEqual(code, 0);
      assert.equal(calls.length, 1, "one call, then it stops");
      assert.deepEqual(sleeps, [], "no wait for a retry");
      assert.match(log.lines.error[0], new RegExp(`refused the bot token \\(${status}\\)`));
      assert.match(log.lines.error[0], /bot_tokens:issue/);
      assert.ok(!log.lines.error[0].includes(TOKEN), "the token is not logged");
    });
  });
}

test("a 503 is logged and retried after the idle wait, pass after pass", async () => {
  await withServer(() => [503, { error: "unavailable" }], async ({ base, calls }) => {
    const log = recorder();
    const sleeps = [];
    const code = await run({ api: makeApi({ base, token: TOKEN }), log, sleep: async (ms) => { sleeps.push(ms); }, passes: 3 });
    assert.equal(code, 0, "still running when the test stops it");
    assert.equal(calls.length, 3, "it kept asking");
    assert.deepEqual(sleeps, [POLL_IDLE_MS, POLL_IDLE_MS, POLL_IDLE_MS]);
    assert.equal(log.lines.warn.length, 3);
    assert.match(log.lines.warn[0], /answered 503; trying again/);
    assert.deepEqual(log.lines.error, []);
  });
});

test("a network failure is retried, not treated as a refused token", async () => {
  const log = recorder();
  const api = makeApi({ base: "http://127.0.0.1:9", token: TOKEN, fetchImpl: async () => { throw new TypeError("fetch failed"); } });
  const code = await run({ api, log, sleep: async () => {}, passes: 2 });
  assert.equal(code, 0);
  assert.equal(log.lines.warn.length, 2);
  assert.ok(!(new TypeError("x") instanceof TokenRejected));
});
