import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { secondsLeft, SplashGate, COUNT_TICK_MS, SEARCH_POLL_MS, SPLASH_POLL_MS } from "cyvasse/seek_splash"

// The Play Now searching page (task play-now-matchmaking;
// app/views/live_seeks/show). It counts down to the end of the search on the
// server's clock and asks the server once a second. The "You vs them" splash
// starts the instant the ring reads 0, a match is found, or the player picks
// the computer; the server's answer fills in the opponent and the game opens
// once the splash has run (cyvasse/seek_splash).
export default class extends Controller {
  static targets = ["count", "searching", "splash", "you", "opponent", "computerTag", "message", "youInitial", "opponentInitial", "progress"]
  static values = { url: String, endsAt: String, serverTime: String, splashMs: Number, you: String }

  connect() {
    this.gate = new SplashGate(this.splashMsValue)
    this.offset = Date.parse(this.serverTimeValue) - Date.now()
    this.countTimer = setInterval(() => this.renderCount(), COUNT_TICK_MS)
    this.renderCount()
    this.poll()
  }

  disconnect() {
    clearInterval(this.countTimer)
    clearTimeout(this.pollTimer)
    clearTimeout(this.openTimer)
  }

  // The system test moves the end of the search by rewriting this value.
  endsAtValueChanged() {
    this.endsAt = Date.parse(this.endsAtValue)
    if (this.gate) this.renderCount()
  }

  renderCount() {
    const left = secondsLeft(this.endsAt, Date.now() + this.offset)
    this.countTarget.textContent = left
    if (left === 0) this.startSplash()
  }

  async poll() {
    clearTimeout(this.pollTimer)
    if (this.gate.url || this.asking) return
    this.asking = true
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (response.ok) {
        const data = await response.json()
        if (data.status === "matched") return this.matched(data)
        if (data.server_time) this.offset = Date.parse(data.server_time) - Date.now()
      }
    } catch {
      // A missed poll just waits for the next one.
    } finally {
      this.asking = false
    }
    if (!this.gate.url) this.pollTimer = setTimeout(() => this.poll(), this.gate.started ? SPLASH_POLL_MS : SEARCH_POLL_MS)
  }

  // "Play the computer now": the splash starts at once and the form's answer
  // names the computer; without it the form submits as a plain POST.
  async playComputer(event) {
    event.preventDefault()
    const form = event.target
    this.startSplash({ ask: false })
    try {
      const response = await fetch(form.action, { method: "POST", body: new FormData(form), headers: { Accept: "application/json" }, credentials: "same-origin" })
      const data = response.ok ? await response.json() : null
      if (data?.status === "matched") return this.matched(data)
    } catch {
      // Fall through to the plain form.
    }
    form.submit()
  }

  // `ask`: poll now rather than at the next second.
  startSplash({ ask = true } = {}) {
    if (!this.gate.start(Date.now())) return
    clearInterval(this.countTimer)
    this.fill(this.youValue, "…")
    this.searchingTarget.hidden = true
    this.splashTarget.hidden = false
    // The bar empties over the splash.
    const bar = this.progressTarget
    bar.style.transition = "none"
    bar.style.transform = "scaleX(1)"
    requestAnimationFrame(() => requestAnimationFrame(() => {
      bar.style.transition = `transform ${this.splashMsValue}ms linear`
      bar.style.transform = "scaleX(0)"
    }))
    if (ask) this.poll()
  }

  matched(data) {
    clearTimeout(this.pollTimer)
    this.startSplash({ ask: false })
    this.fill(data.you, data.opponent)
    if (data.opponent_portrait) this.portrait(this.opponentInitialTarget, data.opponent_portrait, data.opponent)
    this.computerTagTarget.hidden = !data.computer
    this.gate.arrive(data.match_url)
    clearTimeout(this.openTimer)
    this.openTimer = setTimeout(() => Turbo.visit(this.gate.url), this.gate.wait(Date.now()))
  }

  fill(you, opponent) {
    this.youTarget.textContent = you
    this.opponentTarget.textContent = opponent
    this.youInitialTarget.textContent = initial(you)
    this.opponentInitialTarget.textContent = initial(opponent)
  }

  // A computer player's portrait in place of its initial.
  portrait(target, src, name) {
    const img = document.createElement("img")
    img.src = src
    img.alt = name || ""
    img.className = "live-seek-portrait"
    img.dataset.avatar = "bot-portrait"
    target.replaceChildren(img)
    target.classList.add("live-seek-avatar-portrait")
  }
}

function initial(name) {
  if (!name || name === "…") return "?"
  return name.replace(/^Guest_/, "G").charAt(0).toUpperCase()
}
