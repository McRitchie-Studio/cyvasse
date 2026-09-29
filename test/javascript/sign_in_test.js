// [unit] The sign-in modal's magic-link request: what it posts to the
// engine's /magic_link, and that a refusal rejects so the modal says so.
import { test } from "node:test";
import assert from "node:assert/strict";

import { postMagicLink } from "cyvasse/sign_in";

function fakeFetch(status, payload) {
  const calls = [];
  const fn = async (url, options) => {
    calls.push({ url, options });
    return { ok: status < 400, json: async () => payload };
  };
  return { fn, calls };
}

test("posts the email and the way back, with the CSRF token", async () => {
  const { fn, calls } = fakeFetch(200, { success: true });
  await postMagicLink("arya@example.com", "/matches/7?claim=abc", { fetch: fn, csrf: "tok" });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "/magic_link");
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].options.headers["X-CSRF-Token"], "tok");
  const body = new URLSearchParams(calls[0].options.body);
  assert.equal(body.get("email"), "arya@example.com");
  assert.equal(body.get("return_to"), "/matches/7?claim=abc");
});

test("leaves the way back out when there is none", async () => {
  const { fn, calls } = fakeFetch(200, { success: true });
  await postMagicLink("arya@example.com", null, { fetch: fn, csrf: "" });
  assert.equal(new URLSearchParams(calls[0].options.body).has("return_to"), false);
});

test("rejects on an HTTP error or a refusal", async () => {
  await assert.rejects(postMagicLink("a@b.co", null, { fetch: fakeFetch(500, {}).fn, csrf: "" }));
  await assert.rejects(postMagicLink("a@b.co", null, { fetch: fakeFetch(200, { success: false, error: "no" }).fn, csrf: "" }), /no/);
});
