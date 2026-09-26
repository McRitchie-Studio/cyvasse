import { Controller } from "@hotwired/stimulus"

// Saved lineups in the setup panel (epic cyvasse-revival piece 10b;
// app/views/setups/_panel.html.erb). It knows the player's three slots, not
// the game: loading one dispatches `cyvasse-setups:load` with the lineup,
// which the board (cyvasse-game or cyvasse-match#loadLineup) places and marks
// `loaded`; saving dispatches `cyvasse-setups:collect`, which the board
// answers with the army on it, then posts that to the server. A slot changes
// on the page only once the server has saved it.
export default class extends Controller {
  static targets = ["slot", "name", "message"]
  static values = { url: String }

  load(event) {
    const lineup = event.currentTarget.dataset.lineup
    if (!lineup) return
    const detail = { lineup, loaded: false }
    this.dispatch("load", { detail })
    this.say(detail.loaded ? `Loaded ${event.currentTarget.textContent.trim()}.` : "That lineup cannot be placed now.")
  }

  async save(event) {
    const slot = Number(event.currentTarget.closest("[data-slot]").dataset.slot)
    const name = this.nameTarget.value.trim()
    if (!name) {
      this.nameTarget.focus()
      return this.say("Name the lineup first.")
    }
    const detail = { lineup: null }
    this.dispatch("collect", { detail })
    if (!detail.lineup) return this.say("Place your whole army before saving it.")

    let data = null
    let ok = false
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin",
        body: JSON.stringify({ slot, name, lineup: detail.lineup })
      })
      ok = response.ok
      data = await response.json()
    } catch {
      data = null
    }
    if (data?.slots) this.draw(data.slots)
    if (ok) {
      this.nameTarget.value = ""
      this.say(`Saved ${name} to slot ${slot}.`)
    } else {
      this.say(data?.error ? `Not saved: ${data.error}.` : "Could not reach the server. Try again.")
    }
  }

  draw(slots) {
    for (const { slot, name, lineup } of slots) {
      const row = this.slotTargets.find((node) => Number(node.dataset.slot) === slot)
      const button = row?.querySelector("[data-slot-load]")
      if (!button) continue
      button.textContent = name || (lineup ? `Lineup ${slot}` : `Empty slot ${slot}`)
      button.dataset.lineup = lineup || ""
      button.disabled = !lineup
    }
  }

  say(text) {
    this.messageTarget.textContent = text
    this.messageTarget.hidden = false
  }
}

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content ?? ""
}
