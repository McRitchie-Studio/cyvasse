import { Controller } from "@hotwired/stimulus"
import { OPENINGS, openingLineup } from "cyvasse/openings"

// The opening picker in the setup panel (app/views/setups/_openings). It
// lists the twenty openings of cyvasse/openings.js and shows the idea of the
// one chosen; "Load" dispatches `cyvasse-openings:load` with its lineup, which
// the board (cyvasse-game or cyvasse-match#loadLineup) places and marks
// `loaded`, exactly as a saved lineup is loaded.
export default class extends Controller {
  static targets = ["select", "idea", "message"]

  connect() {
    this.selectTarget.replaceChildren(...OPENINGS.map(({ slug, name }) => {
      const option = document.createElement("option")
      option.value = slug
      option.textContent = name
      return option
    }))
    this.choose()
  }

  choose() {
    this.ideaTarget.textContent = this.chosen.idea
    this.messageTarget.hidden = true
  }

  load() {
    const opening = this.chosen
    const detail = { lineup: openingLineup(opening), loaded: false }
    this.dispatch("load", { detail })
    this.messageTarget.textContent = detail.loaded ? `Loaded ${opening.name}.` : "That opening cannot be placed now."
    this.messageTarget.hidden = false
  }

  get chosen() {
    return OPENINGS.find(({ slug }) => slug === this.selectTarget.value) ?? OPENINGS[0]
  }
}
