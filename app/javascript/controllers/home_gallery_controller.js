import { Controller } from "@hotwired/stimulus"

// The front door's background (pages/_home_gallery): one action shot per
// piece, crossfading from one to the next every `interval` ms. The server
// picks the first at random and gives only it a src; each later slide's art
// is filled in from its data-src a slide ahead of its turn, so a visitor who
// leaves early downloads one image. A slide whose art has not arrived yet
// waits for the next tick rather than fading in blank.
//
// A visitor who asks for less motion sees the first slide, still: the
// controller never advances (and loads nothing more) while
// prefers-reduced-motion is set. A hidden tab does not advance either.
//
// data-home-gallery-state on the element reads "playing" or "still", and
// data-home-gallery-piece names the slide on show, for the system test.
export default class extends Controller {
  static targets = ["slide", "caption"]
  static values = { interval: { type: Number, default: 7000 } }

  connect() {
    // A Turbo snapshot restores the slide that was on show.
    this.index = Math.max(0, this.slideTargets.findIndex((slide) => slide.classList.contains("is-active")))
    this.motion = window.matchMedia?.("(prefers-reduced-motion: reduce)")
    this.onMotion = () => this.sync()
    this.motion?.addEventListener?.("change", this.onMotion)
    this.sync()
  }

  disconnect() {
    this.stop()
    this.motion?.removeEventListener?.("change", this.onMotion)
  }

  sync() {
    if (this.motion?.matches || this.slideTargets.length < 2) this.stop()
    else this.start()
    this.element.dataset.homeGalleryPiece = this.slideTargets[this.index]?.dataset.piece ?? ""
  }

  start() {
    this.element.dataset.homeGalleryState = "playing"
    if (this.timer) return
    // The next slide's art, once the page (and so the first slide) is in.
    if (document.readyState === "complete") this.load(this.nextIndex)
    else window.addEventListener("load", () => this.load(this.nextIndex), { once: true })
    this.timer = setInterval(() => this.advance(), this.intervalValue)
  }

  stop() {
    this.element.dataset.homeGalleryState = "still"
    clearInterval(this.timer)
    this.timer = null
  }

  advance() {
    if (document.hidden) return
    const next = this.nextIndex
    const image = this.load(next)
    if (!image?.complete || !image.naturalWidth) return

    this.show(next)
    this.load(this.nextIndex)
  }

  show(index) {
    this.index = index
    this.slideTargets.forEach((slide, i) => slide.classList.toggle("is-active", i === index))
    this.captionTargets.forEach((caption, i) => caption.classList.toggle("is-active", i === index))
    this.element.dataset.homeGalleryPiece = this.slideTargets[index].dataset.piece
  }

  get nextIndex() {
    return (this.index + 1) % this.slideTargets.length
  }

  // Give a slide its art (the <source> first, so the browser picks the right
  // crop before the <img> asks), and answer its <img>.
  load(index) {
    const slide = this.slideTargets[index]
    for (const source of slide.querySelectorAll("source[data-srcset]")) {
      source.srcset = source.dataset.srcset
      delete source.dataset.srcset
    }
    const image = slide.querySelector("img")
    if (image?.dataset.src) {
      image.src = image.dataset.src
      delete image.dataset.src
    }
    return image
  }
}
