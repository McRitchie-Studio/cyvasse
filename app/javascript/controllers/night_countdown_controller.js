import { Controller } from "@hotwired/stimulus"
import { TICK_MS, phaseAt, countdownParts, pad, localTimeLabel } from "cyvasse/night_clock"

// Cyvasse Night's hero (nights/show): the start time in the visitor's own
// zone, and a countdown to the start (or, while it runs, to the end) on the
// SERVER's clock: serverTime is when the page was rendered, so a visitor
// whose computer clock is wrong still sees the right count. When the count
// crosses into the next phase the page reloads once, so Play Now appears at
// 7 PM without a refresh.
export default class extends Controller {
  static targets = ["local", "localTime", "days", "hours", "minutes", "seconds", "label"]
  static values = { start: String, end: String, serverTime: String, phase: String, zone: String }

  connect() {
    this.start = Date.parse(this.startValue)
    this.end = Date.parse(this.endValue)
    const server = Date.parse(this.serverTimeValue)
    this.offset = Number.isFinite(server) ? server - Date.now() : 0
    this.showLocalTime()
    this.tick()
    this.timer = setInterval(() => this.tick(), TICK_MS)
    this.element.dataset.nightCountdownState = "ticking"
  }

  disconnect() {
    clearInterval(this.timer)
  }

  // Shown only when the visitor is outside Mountain time, where the heading
  // already says it.
  showLocalTime() {
    if (!this.hasLocalTarget) return
    let zone = null
    try {
      zone = Intl.DateTimeFormat().resolvedOptions().timeZone
    } catch {
      return
    }
    if (zone === this.zoneValue) return
    this.localTimeTarget.textContent = localTimeLabel(this.start)
    this.localTarget.hidden = false
  }

  tick() {
    const now = Date.now() + this.offset
    const phase = phaseAt(now, this.start, this.end)
    if (phase !== this.phaseValue) return this.advance(phase)
    if (phase === "after") return clearInterval(this.timer)

    const parts = countdownParts(phase === "before" ? this.start : this.end, now)
    if (this.hasDaysTarget) this.daysTarget.textContent = parts.days
    if (this.hasHoursTarget) this.hoursTarget.textContent = pad(parts.hours)
    if (this.hasMinutesTarget) this.minutesTarget.textContent = pad(parts.minutes)
    if (this.hasSecondsTarget) this.secondsTarget.textContent = pad(parts.seconds)
  }

  // The night started (or ended) while the page was open: fetch the page for
  // the new phase. Once per phase per tab, so a server that still disagrees
  // cannot loop the page.
  advance(phase) {
    clearInterval(this.timer)
    const key = `cyvasse-night:${this.startValue}:${phase}`
    try {
      if (sessionStorage.getItem(key)) return
      sessionStorage.setItem(key, "1")
    } catch {
      // No storage (a private window): reload anyway, once, for this page.
    }
    this.element.dataset.nightCountdownState = "advancing"
    window.location.reload()
  }
}
