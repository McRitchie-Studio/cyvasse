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
//   returnTo  a guest's way back here after signing in (the game-over modal)

const REASON_TEXT = {
  king: { 1: "You captured the king. You win.", 0: "Your king fell. You were defeated." },
  resigned: { 1: "Your opponent resigned. You win.", 0: "You resigned." },
  forfeit: { 1: "Your opponent ran out of time. You win.", 0: "You ran out of time and forfeited." }
}

export default class extends GameController {
  static targets = ["error", "deadline", "clock", "clockLabel", "clockSeconds", "clockBar", "notice"]
  static values = {
    state: Object,
    stateUrl: String,
    setupUrl: String,
    moveUrl: String,
    pollMs: { type: Number, default: 15000 },
    returnTo: String
  }

  connect() {
    this.timers = new Set()
    this.buildBoard()
    this.load(this.stateValue)
  }

  disconnect() {
    super.disconnect()
    clearTimeout(this.pollTimer)
    clearInterval(this.clockTimer)
    this.stopAwaitingView()
  }

  // /play's "New game" and the computer's turn have no place here.
  newGame() {}
  runTurn() {}

  // ---- The server's state ----------------------------------------------------

  load(state, { announce = false } = {}) {
    // A live setup that ran out: the army the server placed arrives piece by
    // piece rather than all at once.
    const arriving = this.state?.can_set_up && !state.can_set_up && state.live?.auto_set_up?.you
    // The game ended while this page watched, or a live game that just ended
    // is opened (not an old one, from My games).
    const ended = state.phase === "over" && (this.state ? this.state.phase !== "over" : Boolean(state.live?.just_ended))
    this.state = state
    this.steps = []
    this.pendingJump = null
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
    this.showComputerStep()
    if (arriving) this.animateArrival()
    this.startLiveClock()

    if (ended) {
      this.openGameOver()
    } else if (state.phase === "over") {
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
  // this player is still putting together. A live match polls in every
  // phase: its clocks only move when a board asks (LiveMatch#tick!).
  poll() {
    clearTimeout(this.pollTimer)
    const waiting = this.state.phase !== "over" && !this.state.your_turn && !this.state.can_set_up && !this.state.can_accept
    const live = this.state.live && this.state.phase !== "over"
    if (!(waiting || live) || !this.stateUrlValue) return

    this.pollTimer = setTimeout(async () => {
      try {
        const response = await fetch(this.stateUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        if (response.ok) {
          const state = await response.json()
          // A move's own answer can land before an older poll's: never step back.
          if (Number(state.version) < Number(this.state.version)) {
            // Stale: look again next time.
          } else if (state.version !== this.state.version) {
            // Mid-setup, keep the army being placed: only the clock and the
            // opponent move on. Everything else redraws from the server.
            if (this.state.can_set_up && state.can_set_up && state.phase === "setup") {
              this.state = { ...this.state, live: state.live, opponent: state.opponent, version: state.version }
              this.startLiveClock()
            } else {
              return this.load(state, { announce: true })
            }
          } else if (state.live) {
            this.state = { ...this.state, live: state.live }
            this.syncClock()
          }
        }
      } catch {
        // Offline for a moment: look again next time.
      }
      this.poll()
    }, this.pollMsValue)
  }

  // Answers true when the server took the action.
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
      return response.ok
    }
    this.showError("Could not reach the server. Reload the page to see the match.")
    this.holding = false
    return false
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

  // "Ready": the lineup is locked in on the server.
  start() {
    if (!this.state.can_set_up || !this.game.readyToStart || this.holding) return
    this.send(this.setupUrlValue, { lineup: this.game.playerLineup() }).then((ok) => {
      if (ok) this.emailGoal("played_match")
    })
  }

  // ---- Turns -----------------------------------------------------------------

  playClick(hex) {
    if (!this.state.your_turn || this.holding) return
    if (this.actions && (this.actions.moves.includes(hex) || this.actions.attacks.includes(hex))) {
      const from = this.selectedHex
      const before = this.game.jump === 1 ? this.game.snapshot() : null
      const result = this.game.act(from, hex)
      this.steps.push([from, hex])
      // Both steps of a double jump go to the server together, so until the
      // second is made the first can still be taken back (startOver).
      this.pendingJump = result.secondJump ? before : null
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
      for (const { group } of this.hexNodes.values()) group.classList.remove("is-deploy", "is-drop")
      this.paintGround()
    }
    // "Ready" waits for a full army, and for a setup the server still takes.
    this.startButtonTarget.disabled = !this.state.can_set_up || !this.game.readyToStart
  }

  // A live computer plays in steps (LiveMatch#bot_plan): the unit it chose is
  // shown selected, and again before a cavalry unit's second jump.
  showComputerStep() {
    const hex = this.state.live?.bot_selected
    if (hex == null || this.state.phase !== "play" || !this.game.pieceAt(hex)) return
    if (this.state.live.bot_jump === 2) {
      this.game.jump = 2
      this.game.activeHex = hex
    }
    this.select(hex)
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
      text = left > 0 ? `Place your army: ${left} unit${left === 1 ? "" : "s"} left.` : "Your army is in place. Press Ready to lock it in."
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
    // A live match runs on its own clock (renderClock), not the seven days.
    if (!deadline || phase === "over" || this.state.live) {
      this.deadlineTarget.hidden = true
      return
    }
    const when = new Date(deadline).toLocaleString(undefined, { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
    const who = phase === "play" ? (yourTurn ? "Move by" : "Their move is due by") : "Open until"
    this.deadlineTarget.textContent = `${who} ${when}`
    this.deadlineTarget.hidden = false
  }

  // ---- The live clock (LiveMatch) ---------------------------------------------

  startLiveClock() {
    clearInterval(this.clockTimer)
    this.syncClock()
    this.renderLiveNotice()
    if (!this.hasClockTarget) return
    this.renderClock()
    if (this.state.live && this.state.phase !== "over") this.clockTimer = setInterval(() => this.renderClock(), 200)
  }

  // The server's clock, so a fast or slow laptop does not skew the countdown.
  syncClock() {
    if (this.state.live?.server_time) this.clockOffset = Date.parse(this.state.live.server_time) - Date.now()
  }

  renderClock() {
    const live = this.state.live
    const clock = live?.clock
    const them = this.state.opponent.username
    this.clockTarget.hidden = !live || this.state.phase === "over" || (!clock && !live.thinking)
    if (this.clockTarget.hidden) return

    this.clockTarget.classList.toggle("is-thinking", !!live.thinking)
    if (live.thinking) {
      this.clockTarget.classList.remove("is-warning")
      this.clockLabelTarget.textContent = `${them} is thinking…`
      this.clockSecondsTarget.textContent = ""
      this.clockBarTarget.style.width = "100%"
      return
    }

    const remaining = Math.max(0, (Date.parse(clock.ends_at) - (Date.now() + (this.clockOffset || 0))) / 1000)
    const mine = clock.kind === "setup" ? this.state.can_set_up : this.state.your_turn
    const warning = remaining <= clock.warning
    let label
    if (clock.kind === "setup") label = mine ? "Set up your army" : `Waiting for ${them} to set up`
    else label = mine ? "Your move" : `${them}'s move`
    if (warning && mine) label = clock.kind === "setup" ? "Hurry: set up your board!" : "Hurry: make your move!"

    this.clockTarget.classList.toggle("is-warning", warning)
    this.clockTarget.dataset.clockKind = clock.kind
    this.clockLabelTarget.textContent = label
    this.clockSecondsTarget.textContent = `${Math.ceil(remaining)}s`
    this.clockBarTarget.style.width = `${Math.min(100, (remaining / clock.seconds) * 100)}%`

    // Out of time: ask the server now rather than at the next poll.
    if (remaining === 0 && this.firedFor !== clock.ends_at) {
      this.firedFor = clock.ends_at
      clearTimeout(this.pollTimer)
      this.pollTimer = setTimeout(() => this.poll(), 300)
    }
  }

  renderLiveNotice() {
    if (!this.hasNoticeTarget) return
    const live = this.state.live
    const them = this.state.opponent.username
    let text = ""
    if (live) {
      if (live.taken_over.you) text = "You missed two clocks, so a computer player has taken your seat for the rest of this game."
      else if (live.taken_over.opponent) text = `${them} missed two clocks, so a computer player has taken their seat.`
      else if (live.auto_set_up.you && live.strikes.you === 1) text = "Time ran out, so your army was placed for you. Miss one more clock and a computer player takes your seat."
      else if (live.strikes.you === 1) text = "You missed a clock and a move was made for you. Miss one more and a computer player takes your seat."
      else if (live.strikes.opponent === 1) text = `${them} missed a clock.`
    }
    this.noticeTarget.textContent = text
    this.noticeTarget.hidden = !text
  }

  // Each of this player's units fades in, one after another, in board order.
  animateArrival() {
    const nodes = [...this.hexNodes.entries()]
      .filter(([, node]) => node.group.dataset.team === "1")
      .sort(([a], [b]) => a - b)
      .map(([, node]) => node.group)
    this.boardTarget.classList.add("is-arrival")
    for (const group of nodes) group.classList.add("is-arriving")
    const step = this.paceValue === 0 ? 0 : 70
    nodes.forEach((group, i) => setTimeout(() => group.classList.remove("is-arriving"), 120 + i * step))
    setTimeout(() => this.boardTarget.classList.remove("is-arrival"), 120 + nodes.length * step + 400)
  }

  // The engine's modal (modals/_game_over): the result, then sign in (a
  // guest) or play again. Closed, it leaves the final board to look over.
  // Until Alpine has the modal store, the result stays on the board.
  openGameOver() {
    // Out of sight (another tab, window or app), it waits for the player:
    // opened behind their back, the click that brings them back lands on
    // the backdrop and closes it unseen.
    if (!inView()) {
      this.banner(this.outcomeText(), null, { stay: true })
      this.awaitView()
      return
    }
    const store = window.Alpine?.store?.("modals")
    if (!store) {
      this.banner(this.outcomeText(), null, { stay: true })
      document.addEventListener("alpine:initialized", () => this.state.phase === "over" && this.openGameOver(), { once: true })
      return
    }
    this.hideBanner()
    if (store.isLive("game-over")) return
    store.open("game-over", {
      ariaLabel: "Game over",
      result: this.outcomeText(),
      boardWin: Boolean(this.state.live?.board_win),
      returnTo: this.returnToValue || null
    })
  }

  awaitView() {
    if (this.onView) return
    this.onView = () => {
      if (!inView()) return
      this.stopAwaitingView()
      if (this.state.phase === "over") this.openGameOver()
    }
    document.addEventListener("visibilitychange", this.onView)
    window.addEventListener("focus", this.onView)
  }

  stopAwaitingView() {
    if (!this.onView) return
    document.removeEventListener("visibilitychange", this.onView)
    window.removeEventListener("focus", this.onView)
    this.onView = null
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

function inView() {
  return document.visibilityState === "visible" && document.hasFocus()
}

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content ?? ""
}
