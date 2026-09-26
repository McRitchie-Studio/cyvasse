import GameController from "controllers/cyvasse_game_controller"
import { Game, PLAYER } from "cyvasse/game"

// The board for an online match (matches/show): the /play board, driven by
// the server instead of the computer.
//
// The server sends the match from this player's seat (Match#state_for): their
// army is team 1 on the bottom rows whichever seat they hold. The browser
// offers the moves the engine allows and posts whole turns (one step, or two
// for a cavalry double jump); the server checks each turn by the same rules
// (CyvasseRules, held to app/javascript/cyvasse by a recorded fixture) and
// answers with the new state, which is redrawn as is. A refused turn comes
// back with the true state and a message. While the opponent is to move, the
// page polls for their turn.
//
// Values
//   state     the match as Match#state_for renders it
//   stateUrl  GET, JSON state      setupUrl  POST { lineup }
//   moveUrl   POST { steps }       pollMs    how often to look for news

const REASON_TEXT = {
  king: { 1: "You captured the king. You win.", 0: "Your king fell. You were defeated." },
  resigned: { 1: "Your opponent resigned. You win.", 0: "You resigned." },
  forfeit: { 1: "Your opponent ran out of time. You win.", 0: "You ran out of time and forfeited." }
}

export default class extends GameController {
  static targets = ["error", "deadline"]
  static values = {
    state: Object,
    stateUrl: String,
    setupUrl: String,
    moveUrl: String,
    pollMs: { type: Number, default: 15000 }
  }

  connect() {
    this.timers = new Set()
    this.buildBoard()
    this.load(this.stateValue)
  }

  disconnect() {
    super.disconnect()
    clearTimeout(this.pollTimer)
  }

  // /play's "New game" and the computer's turn have no place here.
  newGame() {}
  runTurn() {}

  // ---- The server's state ----------------------------------------------------

  load(state, { announce = false } = {}) {
    this.state = state
    this.steps = []
    this.holding = false
    this.clearSelection()
    this.game = Game.restore({
      phase: state.phase,
      turn: state.turn,
      offense: state.offense,
      units: state.units,
      lastMove: state.last_move,
      utilMove: state.util_move,
      winner: state.winner
    })
    this.element.dataset.matchStatus = state.status
    this.element.dataset.yourTurn = state.your_turn ? "true" : "false"
    this.setupControlsTarget.hidden = !state.can_set_up
    this.opponentTarget.textContent = state.opponent.username
    this.renderDeadline()
    this.render()

    if (state.phase === "over") {
      this.banner(this.outcomeText(), null, { stay: true })
    } else if (announce && state.phase === "play") {
      this.banner(state.your_turn ? `Turn ${state.turn} · Your move` : `Turn ${state.turn} · ${state.opponent.username} to move`)
    }
    this.poll()
  }

  // A new polling pace takes effect at once (the system test shortens it).
  pollMsValueChanged() {
    if (this.state) this.poll()
  }

  // Only while waiting on the opponent, and never over a turn or an army
  // this player is still putting together.
  poll() {
    clearTimeout(this.pollTimer)
    const waiting = this.state.phase !== "over" && !this.state.your_turn && !this.state.can_set_up && !this.state.can_accept
    if (!waiting || !this.stateUrlValue) return

    this.pollTimer = setTimeout(async () => {
      try {
        const response = await fetch(this.stateUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        if (response.ok) {
          const state = await response.json()
          if (state.version !== this.state.version) return this.load(state, { announce: true })
        }
      } catch {
        // Offline for a moment: look again next time.
      }
      this.poll()
    }, this.pollMsValue)
  }

  async send(url, body) {
    this.holding = true
    this.showError(null)
    let response
    let data = null
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin",
        body: JSON.stringify(body)
      })
      data = await response.json()
    } catch {
      data = null
    }
    if (data?.state) {
      this.load(data.state, { announce: true })
      if (!response.ok) this.showError(data.error || "The server refused that.")
      return
    }
    this.showError("Could not reach the server. Reload the page to see the match.")
    this.holding = false
  }

  // ---- Setup -----------------------------------------------------------------

  setupClick(hex) {
    if (!this.state.can_set_up) return
    super.setupClick(hex)
  }

  pickFromDock(event) {
    if (!this.state.can_set_up) return
    super.pickFromDock(event)
  }

  randomSetup() {
    if (!this.state.can_set_up) return
    super.randomSetup()
  }

  loadLineup(event) {
    if (!this.state.can_set_up || this.holding) return
    super.loadLineup(event)
  }

  // "Submit army": the lineup is locked in on the server.
  start() {
    if (!this.state.can_set_up || !this.game.readyToStart || this.holding) return
    this.send(this.setupUrlValue, { lineup: this.game.playerLineup() })
  }

  // ---- Turns -----------------------------------------------------------------

  playClick(hex) {
    if (!this.state.your_turn || this.holding) return
    if (this.actions && (this.actions.moves.includes(hex) || this.actions.attacks.includes(hex))) {
      const from = this.selectedHex
      const result = this.game.act(from, hex)
      this.steps.push([from, hex])
      if (result.secondJump) {
        this.render()
        this.select(this.game.activeHex)
        return
      }
      this.clearSelection()
      this.render()
      this.send(this.moveUrlValue, { steps: this.steps })
      return
    }
    if (this.game.selectableHexes().includes(hex)) this.select(hex)
  }

  // ---- Drawing ---------------------------------------------------------------

  render() {
    super.render()
    if (this.game.phase === "setup" && !this.state.can_set_up) {
      for (const { group } of this.hexNodes.values()) group.classList.remove("is-deploy")
    }
  }

  renderStatus() {
    const state = this.state
    const them = state.opponent.username
    let text
    if (state.phase === "over") {
      text = this.outcomeText()
    } else if (state.phase === "play") {
      if (!state.your_turn) text = `Turn ${state.turn}: waiting for ${them} to move.`
      else text = this.game.jump === 2 ? `Turn ${state.turn}: your cavalry jumps again.` : `Turn ${state.turn}: your move.`
    } else if (state.can_accept) {
      text = `${them} challenged you. Accept to set up your army.`
    } else if (state.can_set_up) {
      const left = this.game.teamUnits(PLAYER, "unplaced").length
      text = left > 0 ? `Place your army: ${left} unit${left === 1 ? "" : "s"} left.` : "Your army is ready. Submit it."
    } else if (state.status === "pending") {
      text = `Your army is in place. Waiting for ${them} to accept.`
    } else {
      text = `Your army is in place. Waiting for ${them} to set up.`
    }
    this.statusTarget.textContent = text
  }

  renderDeadline() {
    if (!this.hasDeadlineTarget) return
    const { deadline, phase, your_turn: yourTurn } = this.state
    if (!deadline || phase === "over") {
      this.deadlineTarget.hidden = true
      return
    }
    const when = new Date(deadline).toLocaleString(undefined, { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
    const who = phase === "play" ? (yourTurn ? "Move by" : "Their move is due by") : "Open until"
    this.deadlineTarget.textContent = `${who} ${when}`
    this.deadlineTarget.hidden = false
  }

  outcomeText() {
    const { winner, finish_reason: reason, opponent } = this.state
    if (reason === "draw") return "Neither side can move. A draw."
    if (reason === "expired") return `This challenge with ${opponent.username} expired unplayed.`
    if (reason === "abandoned") return "This match was left unfinished on the old Cyvasse."
    const lines = REASON_TEXT[reason]
    if (lines && winner !== null) return lines[winner]
    return winner === 1 ? "You win." : winner === 0 ? "You were defeated." : "The match is over."
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message || ""
    this.errorTarget.hidden = !message
  }
}

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content ?? ""
}
