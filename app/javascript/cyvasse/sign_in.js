// The sign-in modal's magic-link request (app/views/modals/_auth): POST the
// email, and the page to return to, to the engine's /magic_link. Rejects on
// any failure, so the modal can say so.
export async function postMagicLink(email, returnTo, { fetch: fetchFn = globalThis.fetch, csrf = csrfToken() } = {}) {
  const body = new URLSearchParams()
  body.set("email", email || "")
  if (returnTo) body.set("return_to", returnTo)
  const response = await fetchFn("/magic_link", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json", "X-CSRF-Token": csrf },
    credentials: "same-origin",
    body: body.toString()
  })
  let payload = {}
  try { payload = await response.json() } catch { payload = {} }
  if (!response.ok || payload.success === false) throw new Error(payload.error || "Magic link request failed")
  return payload
}

function csrfToken() {
  return globalThis.document?.querySelector("meta[name='csrf-token']")?.content ?? ""
}
