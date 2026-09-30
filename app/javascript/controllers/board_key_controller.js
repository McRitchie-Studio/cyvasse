import { Controller } from "@hotwired/stimulus"
import { placeKey } from "cyvasse/board_key"

// The board key (games/_threat_toggle): a <details> whose panel opens over
// the board. Each time it opens, and on a resize while it is open, it is
// placed where it fits the screen (cyvasse/board_key): below its "?", or
// above it, capped to the room there so it scrolls inside itself.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.onResize = () => this.place()
    window.addEventListener("resize", this.onResize)
    this.place()
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
  }

  place() {
    const panel = this.panelTarget
    delete this.element.dataset.placement
    panel.style.maxHeight = ""
    if (!this.element.open) return

    const toggle = this.element.querySelector("summary").getBoundingClientRect()
    const nav = document.querySelector("header[data-pin=nav]")
    const { placement, maxHeight } = placeKey({
      toggleTop: toggle.top,
      toggleBottom: toggle.bottom,
      viewportHeight: document.documentElement.clientHeight,
      navBottom: nav ? nav.getBoundingClientRect().bottom : 0,
      panelHeight: panel.scrollHeight
    })
    this.element.dataset.placement = placement
    if (maxHeight !== null) panel.style.maxHeight = `${maxHeight}px`
  }
}
