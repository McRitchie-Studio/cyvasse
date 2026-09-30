import { Controller } from "@hotwired/stimulus"
import { fitName } from "cyvasse/name_fit"

// A player's name sized to fit its box (cyvasse/name_fit): the Play Now
// splash and the match's versus card. It fits again when the name changes
// (the splash fills its names in) and when its box changes width (a resize,
// or the splash showing). Only a width change refits: the fit itself changes
// the box's height, and refitting on that would loop.
export default class extends Controller {
  static values = { floor: { type: Number, default: 11 } }

  connect() {
    this.box = this.element.parentElement
    this.mutations = new MutationObserver(() => this.fit())
    this.mutations.observe(this.element, { childList: true, characterData: true, subtree: true })
    this.resizes = new ResizeObserver(() => {
      if (this.box.clientWidth !== this.width) this.fit()
    })
    this.resizes.observe(this.box)
    this.fit()
  }

  disconnect() {
    this.mutations.disconnect()
    this.resizes.disconnect()
  }

  fit() {
    this.width = this.box.clientWidth
    fitName(this.element, { floor: this.floorValue })
  }
}
