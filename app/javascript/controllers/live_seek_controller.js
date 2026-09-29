import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The Play Now searching page (task play-now-matchmaking;
// app/views/live_seeks/show). It counts down to the end of the search on the
// server's clock, asks the server once a second, and once a match is made
// shows "You vs them" for the splash time before moving into the game.
export default class extends Controller {
  static targets = ["count", "searching", "splash", "you", "opponent", "computerTag", "message", "youInitial", "opponentInitial", "progress"]
  static values = { url: String, endsAt: String, serverTime: String }

  connect() {
    this.offset = Date.parse(this.serverTimeValue) - Date.now()
    this.endsAt = Date.parse(this.endsAtValue)
    this.countTimer = setInterval(() => this.renderCount(), 200)
    this.renderCount()
    this.poll()
  }

  disconnect() {
    clearInterval(this.countTimer)
    clearTimeout(this.pollTimer)
    clearTimeout(this.splashTimer)
  }

  renderCount() {
    const left = Math.max(0, Math.ceil((this.endsAt - (Date.now() + this.offset)) / 1000))
    this.countTarget.textContent = left
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (response.ok) {
        const data = await response.json()
        if (data.status === "matched") return this.matched(data)
        if (data.server_time) this.offset = Date.parse(data.server_time) - Date.now()
      }
    } catch {
      // A missed poll just waits for the next one.
    }
    this.pollTimer = setTimeout(() => this.poll(), 1000)
  }

  matched(data) {
    clearInterval(this.countTimer)
    this.youTarget.textContent = data.you
    this.opponentTarget.textContent = data.opponent
    this.youInitialTarget.textContent = initial(data.you)
    this.opponentInitialTarget.textContent = initial(data.opponent)
    this.computerTagTarget.hidden = !data.computer
    this.searchingTarget.hidden = true
    this.splashTarget.hidden = false
    // The bar empties over the splash, then the game opens.
    const bar = this.progressTarget
    bar.style.transition = "none"
    bar.style.transform = "scaleX(1)"
    requestAnimationFrame(() => requestAnimationFrame(() => {
      bar.style.transition = `transform ${data.splash_ms}ms linear`
      bar.style.transform = "scaleX(0)"
    }))
    this.splashTimer = setTimeout(() => Turbo.visit(data.match_url), data.splash_ms)
  }
}

function initial(name) {
  return (name || "?").replace(/^Guest_/, "G").charAt(0).toUpperCase()
}
