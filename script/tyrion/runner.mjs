// Tyrion's runner (task tyrion-runner): plays the `tyrion` account's matches
// on the Cyvasse server from any machine that can reach it. It only ever
// calls out (GET/POST /api/bot, Api::Bot on the server); nothing on this
// machine listens. Run it with bin/tyrion; the design and the threat model
// are the hub's mcritchie-studio docs/agents/agents/tyrion/runtime.md.
//
//   CYVASSE_BOT_TOKEN   required: `bin/rails "bot_tokens:issue[tyrion]"` on the server
//   CYVASSE_URL         default https://cyvasse.mcritchie.studio
//   ANTHROPIC_API_KEY   optional: without it he chats from stock lines
//   TYRION_CHAT_MODEL   optional: default claude-opus-5-5

import { chooseSetup, chooseTurn, gameFromState } from "./brain.mjs";
import { ChatBudget, asksForThePurse, filterLine, stockLine } from "./voice.mjs";

export const POLL_LIVE_MS = 2_000;
export const POLL_IDLE_MS = 30_000;

export function makeApi({ base, token, fetchImpl = fetch }) {
  return async function api(method, path, body) {
    const response = await fetchImpl(new URL(path, base), {
      method,
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json", ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined
    });
    const json = await response.json().catch(() => ({}));
    if (response.ok || response.status === 422) return { status: response.status, body: json };
    throw new Error(`${method} ${path} answered ${response.status}`);
  };
}

// One pass over the inbox. `state` carries the cursor and the chat budget
// between passes. Returns whether a live match is on (poll faster).
export async function tick({ api, state, chat = null, secrets = [], rng = Math.random, log = console }) {
  const { body: inbox } = await api("GET", `/api/bot/inbox?after=${state.cursor ?? 0}`);
  const opponents = new Map(inbox.matches.map((m) => [m.id, m.opponent]));

  for (const match of inbox.matches) {
    if (match.action === "setup") {
      const { slug, lineup } = chooseSetup(rng);
      const { status } = await api("POST", `/api/bot/matches/${match.id}/setup`, { lineup });
      log.info(`tyrion: match ${match.id} set up ${slug} (${status})`);
      if (status === 200 && !state.greeted.has(match.id)) {
        state.greeted.add(match.id);
        await say(api, match.id, stockLine("greet", rng), secrets);
      }
    } else if (match.action === "move") {
      const { body: view } = await api("GET", `/api/bot/matches/${match.id}`);
      if (!view.your_turn) continue;
      const steps = chooseTurn(gameFromState(view), rng);
      if (!steps) continue;
      const { status, body } = await api("POST", `/api/bot/matches/${match.id}/moves`, { steps });
      log.info(`tyrion: match ${match.id} turn ${view.turn} ${JSON.stringify(steps)} (${status}${body.error ? `: ${body.error}` : ""})`);
    }
  }

  // A runner that has just started has not read the chat before: it catches
  // up in silence rather than answering every message since the beginning.
  if (state.cursor === null) {
    state.cursor = inbox.cursor ?? 0;
    return inbox.matches.some((m) => m.live);
  }

  for (const message of inbox.messages) {
    state.cursor = Math.max(state.cursor, message.id);
    const history = state.chats.get(message.match_id) ?? [];
    history.push({ from: "opponent", text: message.text });
    state.chats.set(message.match_id, history.slice(-8));
    if (!opponents.has(message.match_id) || !state.budget.allow(message.match_id, message.from)) continue;

    let line = null;
    if (asksForThePurse(message.text)) {
      line = stockLine("purse", rng);
    } else if (chat) {
      line = filterLine(await chat.reply({ board: `match ${message.match_id}, against ${message.from}`, chat: history }), secrets);
    }
    const posted = line ?? stockLine("reply", rng);
    await say(api, message.match_id, posted, secrets);
    history.push({ from: "tyrion", text: posted });
  }
  state.cursor = Math.max(state.cursor, inbox.cursor ?? 0);
  return inbox.matches.some((m) => m.live);
}

async function say(api, matchId, text, secrets) {
  const line = filterLine(text, secrets);
  if (line) await api("POST", `/api/bot/matches/${matchId}/messages`, { message: line });
}

export function newState() {
  return { cursor: null, greeted: new Set(), chats: new Map(), budget: new ChatBudget() };
}

async function main() {
  const token = process.env.CYVASSE_BOT_TOKEN;
  if (!token) {
    console.error("tyrion: set CYVASSE_BOT_TOKEN (bin/rails \"bot_tokens:issue[tyrion]\" on the server)");
    process.exit(1);
  }
  const base = process.env.CYVASSE_URL || "https://cyvasse.mcritchie.studio";
  const { makeChat } = await import("./chat.mjs");
  const chat = await makeChat();
  const api = makeApi({ base, token });
  const secrets = [token, process.env.ANTHROPIC_API_KEY].filter(Boolean);
  const state = newState();
  console.info(`tyrion: at the table on ${base}${chat ? ", chatting" : ", stock lines only"}`);
  for (;;) {
    let live = false;
    try {
      live = await tick({ api, state, chat, secrets });
    } catch (error) {
      console.warn(`tyrion: ${error.message}; trying again`);
    }
    await new Promise((resolve) => setTimeout(resolve, live ? POLL_LIVE_MS : POLL_IDLE_MS));
  }
}

if (import.meta.url === `file://${process.argv[1]}`) main();
