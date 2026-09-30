import { Controller } from "@hotwired/stimulus"

// /rules: a Units-list stat that a Special Rule explains links to that rule's
// card, <a href="#rule-range"> and so on (pages/_unit_card). The plain hash
// link jumps without JS; this scrolls there smoothly (instantly under reduced
// motion), keeps the hash so the link can be shared, and flashes the card for
// 1.5s so the eye lands on it (no flash under reduced motion). A deep link
// such as /rules#rule-trumps flashes its card on arrival too. The card's
// scroll-margin-top (application.css, off the navbar's measured --nav-h)
// keeps it clear of the sticky navbar.
const FLASH = "rule-card-flash"
const FLASH_MS = 1500

export default class extends Controller {
  connect() {
    const card = this.cardFor(window.location.hash)
    if (card) this.flash(card)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  follow(event) {
    const link = event.target.closest("a[href^='#rule-']")
    if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const card = this.cardFor(link.getAttribute("href"))
    if (!card) return

    event.preventDefault()
    history.pushState(history.state, "", link.getAttribute("href"))
    card.scrollIntoView({ behavior: this.reducedMotion ? "auto" : "smooth", block: "start" })
    card.focus({ preventScroll: true })
    this.flash(card)
  }

  cardFor(hash) {
    if (!hash || !hash.startsWith("#rule-")) return null
    return this.element.querySelector(`.special-rule-card[id="${CSS.escape(hash.slice(1))}"]`)
  }

  flash(card) {
    if (this.reducedMotion) return
    clearTimeout(this.timer)
    this.element.querySelectorAll(`.${FLASH}`).forEach((el) => el.classList.remove(FLASH))
    void card.offsetWidth // restart the animation on a second click
    card.classList.add(FLASH)
    this.timer = setTimeout(() => card.classList.remove(FLASH), FLASH_MS)
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
