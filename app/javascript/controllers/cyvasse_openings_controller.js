import { Controller } from "@hotwired/stimulus"
import { OPENINGS, openingLineup, openingFor } from "cyvasse/openings"

// The opening picker in the setup panel (app/views/setups/_openings). It
// lists the openings of cyvasse/openings.js and shows the idea of the one
// chosen; "Load" dispatches `cyvasse-openings:load` with its lineup, which
// the board (cyvasse-game or cyvasse-match#loadLineup) places and marks
// `loaded`, exactly as a saved lineup is loaded.
//
// The board says what stands on it (`<board>:lineup`, on every redraw that
// changes the player's army), and the picker follows: a whole army that is an
// opening (Smart Setup, New Setup, a load) selects that opening; any other
// whole army ("Place All" around the player's own units, a unit moved by
// hand) selects "Custom". A part-placed army leaves the picker alone.
export const CUSTOM = "custom"
const CUSTOM_IDEA = "Your own lineup: it is none of the openings. Pick one to load it instead."

export default class extends Controller {
  static targets = ["select", "idea", "message"]

  connect() {
    const custom = document.createElement("option")
    custom.value = CUSTOM
    custom.textContent = "Custom"
    custom.hidden = true
    this.selectTarget.replaceChildren(...OPENINGS.map(({ slug, name }) => {
      const option = document.createElement("option")
      option.value = slug
      option.textContent = name
      return option
    }), custom)
    this.choose()
  }

  choose() {
    this.ideaTarget.textContent = this.chosen?.idea ?? CUSTOM_IDEA
    this.messageTarget.hidden = true
  }

  // The board's army changed: name what now stands on it.
  reflect({ detail: { lineup } }) {
    if (!lineup) return
    const value = openingFor(lineup)?.slug ?? CUSTOM
    if (this.selectTarget.value === value) return
    this.selectTarget.value = value
    this.ideaTarget.textContent = this.chosen?.idea ?? CUSTOM_IDEA
  }

  load() {
    const opening = this.chosen
    if (!opening) {
      this.messageTarget.textContent = "Pick an opening to load."
      this.messageTarget.hidden = false
      return
    }
    const detail = { lineup: openingLineup(opening), loaded: false }
    this.dispatch("load", { detail })
    this.messageTarget.textContent = detail.loaded ? `Loaded ${opening.name}.` : "That opening cannot be placed now."
    this.messageTarget.hidden = false
  }

  // The opening selected, or null for "Custom".
  get chosen() {
    if (this.selectTarget.value === CUSTOM) return null
    return OPENINGS.find(({ slug }) => slug === this.selectTarget.value) ?? OPENINGS[0]
  }
}
