import { Controller } from "@hotwired/stimulus"
import { Game, PLAYER, COMPUTER } from "cyvasse/game"
import { chooseAction } from "cyvasse/ai"
import { botDelays } from "cyvasse/pacing"
import { HEXES, hexAt, inPlayerZone } from "cyvasse/board"
import { UNIT_TYPES, THREAT_GROUPS } from "cyvasse/units"
import { Banner, passNotice } from "cyvasse/banner"
import { fullMove } from "cyvasse/turns"
import { threats } from "cyvasse/threats"
import { EDGES, hexClaim, resolveEdges, threatRims, PERIMETER_STYLE } from "cyvasse/edges"
import { LastMoveMarker, lastMoveKey } from "cyvasse/last_move"
import { hexCorners, artClipCorners, pointsAttribute } from "cyvasse/art_clip"
import { playIntent, setupIntent } from "cyvasse/selection"
import { smartLineup, smartSetupMode, SMART_LABELS, recentPicks, rememberPick } from "cyvasse/smart_setup"
import { hexLabel, hexStates, selectionNote } from "cyvasse/hex_label"
import { setupScrollBy } from "cyvasse/setup_fit"

// The Cyvasse board at /play: one game against the computer, in the browser.
//
// The rules live in app/javascript/cyvasse (tested under test/javascript);
// this controller only draws a Game and turns clicks into Game calls. The
// look follows the legacy match screen: black hexes with white edges, a soft
// orange glow for the last move that fades over ten seconds (markLastMove,
// cyvasse/last_move), and the ring ripple (animation.js) washing out from a
// selected unit in the legacy colours, one ring every 120 ms. Each lit hex is
// a gradient in its ring's colour under a faint hatch (ringStops, below).
//
// Values
//   skin    which piece art the board draws ("vector" by default); the server
//           resolves `images` for it, so a skin switch is a new images map
//   images  { codename: url } for the chosen skin
//   skins   { skin: images } for every skin, so the switcher (switchSkin) can
//           redraw a game in progress without a reload
//   pace    multiplier on every delay; 1 is the legacy timing, 0 is instant
//           (the system test sets it to play a whole game quickly)

const SVG_NS = "http://www.w3.org/2000/svg"
const W = 60
const H = W * 2 / Math.sqrt(3)
const PAD = 4
const RIPPLE_MS = 120

// Legacy Animation.hslRange: saturation and lightness per ring, brightening
// outward. The dragon's longer reach uses the ten-step table.
const HSL_SHORT = ["40%,30%", "42%,39%", "44%,47%", "46%,50%", "48%,55%", "50%,60%"]
const HSL_LONG = ["40%,30%", "41%,34%", "42%,38%", "43%,42%", "44%,45%", "45%,48%", "46%,51%", "47%,54%", "48%,57%", "50%,60%"]
const HSL_TABLES = { short: HSL_SHORT, long: HSL_LONG }
// Move ring code -> hue (animation.js updateRing). A hex the unit cannot stop
// on (2x, flown over; 5x, blocked) is not a hue: it is sunken, a desaturated
// gray dish, darker at the centre, with no hatch (SUNKEN_STOPS, .is-sunken).
const MOVE_HUE = { 1: 240, 3: 10, 4: 10 }
const SUNKEN_CODES = new Set([2, 5])

// Each lit hex is filled with a radial gradient rather than the flat legacy
// colour: the ring's own hsl() sits at the middle stop, the centre is lighter
// and the edge deeper, so the hex has depth. The hue drifts a little across
// the hex for colour (blue towards cyan at the centre and indigo at the edge);
// the capture red drifts towards crimson, never towards the selection orange.
// One gradient per hue, table and ripple step, so the outward brightening of
// the ripple still reads. [centre, edge] hue offsets:
const RING_DRIFT = { 240: [-16, 14], 10: [-4, -18], 280: [-10, 8] }

function ringStops(hue, entry) {
  const [s, l] = entry.split(",").map((part) => parseFloat(part))
  const [inner, outer] = RING_DRIFT[hue]
  const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n))
  return [
    ["0%", `hsl(${hue + inner}, ${clamp(s + 14, 0, 100)}%, ${clamp(l + 20, 0, 80)}%)`],
    ["55%", `hsl(${hue}, ${s}%, ${l}%)`],
    ["100%", `hsl(${hue + outer}, ${clamp(s + 10, 0, 100)}%, ${clamp(l - 14, 12, 100)}%)`]
  ]
}

function sunkenStops(entry) {
  const l = parseFloat(entry.split(",")[1])
  return [
    ["0%", `hsl(220, 3%, ${(7 + l * 0.04).toFixed(1)}%)`],
    ["70%", `hsl(220, 4%, ${(11 + l * 0.06).toFixed(1)}%)`],
    ["100%", `hsl(220, 5%, ${(17 + l * 0.1).toFixed(1)}%)`]
  ]
}

function ringFill(hue, table, step) {
  return `url(#ring-${hue}-${table}-${step})`
}

// A cavalry unit's second-jump preview (move codes 6x/7x/8x) is a "ghost" of
// the live ring it previews: move blue, capture red, blocked purple. Its
// gradient is faint and weighted to the rim, the centre nearly clear, and the
// hex takes a dashed edge (game.css .is-ghost) and no hatch, so "possible on
// the second jump" never reads as "move here now".
const PREVIEW_HUE = { 6: 240, 7: 10, 8: 280 }

function ghostStops(hue, entry) {
  const [s, l] = entry.split(",").map((part) => parseFloat(part))
  const [inner, outer] = RING_DRIFT[hue]
  return [
    ["0%", `hsl(${hue + inner}, ${s}%, ${l}%)`, 0.08],
    ["55%", `hsl(${hue}, ${s}%, ${l}%)`, 0.22],
    ["100%", `hsl(${hue + outer}, ${Math.min(100, s + 12)}%, ${l + 4}%)`, 0.6]
  ]
}

// A shooter's range (rangeRings) reads as a zone. Each kind has its own
// gradient, one per ripple step, brightening outward like the move rings:
//   field    1x  the line of fire: a soft red wash, hatched (.is-field)
//   target   2x  an enemy it can hit: a strong crimson, heavy red edge
//   blocked  3x 4x  a mountain in the line and its shadow: dim slate, dashed
// The reds lean to crimson, away from the selection and last-move orange.
const RANGE_KIND = { 1: "field", 2: "target", 3: "blocked", 4: "blocked" }
const RANGE_STOPS = {
  field: (s, l) => [
    ["0%", `hsl(12, ${s + 8}%, ${l * 0.9}%)`, 0.2],
    ["60%", `hsl(4, ${s + 10}%, ${l * 0.85}%)`, 0.3],
    ["100%", `hsl(356, ${s + 14}%, ${l * 0.8}%)`, 0.52]
  ],
  target: (s, l) => [
    ["0%", `hsl(6, 95%, ${Math.min(80, l + 22)}%)`, 1],
    ["45%", `hsl(356, 90%, ${l + 4}%)`, 1],
    ["100%", `hsl(342, 85%, ${Math.max(18, l - 10)}%)`, 1]
  ],
  blocked: (s, l) => [
    ["0%", `hsl(212, 12%, ${l * 0.55}%)`, 0.9],
    ["100%", `hsl(222, 18%, ${l * 0.32}%)`, 0.95]
  ]
}

// The ground under every hex, before any ring lights it: the plain board is a
// cool slate, your setup rows near-black with a faint indigo cast (and the
// hatch, game.css), and once a unit is picked in setup the empty hexes it may
// go to light up. Centre, middle and edge stops; paintGround() applies them.
const GROUND = {
  "hex-base": [["0%", "hsl(218, 10%, 25%)"], ["60%", "hsl(220, 11%, 17%)"], ["100%", "hsl(222, 13%, 10%)"]],
  "hex-deploy": [["0%", "hsl(232, 20%, 12%)"], ["65%", "hsl(236, 24%, 7%)"], ["100%", "hsl(240, 28%, 4%)"]],
  "hex-drop": [["0%", "hsl(226, 72%, 50%)"], ["55%", "hsl(233, 64%, 34%)"], ["100%", "hsl(240, 58%, 20%)"]]
}

// A faint stop is not left see-through, or the page behind the board would
// show through it (white, in the light theme): it is mixed over the slate
// board instead, so the hex stays opaque and reads the same in both themes.
const BOARD_UNDER = [220, 11, 15]

function hslToRgb(h, s, l) {
  s /= 100
  l /= 100
  const k = (n) => (n + h / 30) % 12
  const a = s * Math.min(l, 1 - l)
  return [0, 8, 4].map((n) => 255 * (l - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1))))
}

function overBoard(color, alpha) {
  const [h, s, l] = color.match(/-?[\d.]+/g).map(Number)
  const top = hslToRgb(((h % 360) + 360) % 360, s, l)
  const under = hslToRgb(...BOARD_UNDER)
  const [r, g, b] = top.map((c, i) => Math.round(c * alpha + under[i] * (1 - alpha)))
  return `rgb(${r}, ${g}, ${b})`
}

// Every class a ripple may leave on a hex; render() and each repaint clear
// the lot, so a hex never carries two looks.
const RING_CLASSES = ["is-lit", "is-sunken", "is-ghost", "is-field", "is-target", "is-blocked"]
// Each threat group's outline (renderThreats) is on unless the player turned
// it off; a player who turned off the old single switch starts with both off.
const THREATS_KEY = "cyvasse.showThreats"

function threatsWanted(group) {
  try {
    const stored = window.localStorage.getItem(`${THREATS_KEY}.${group}`) ?? window.localStorage.getItem(THREATS_KEY)
    return stored !== "off"
  } catch {
    return true
  }
}

const RANK_LABEL = { vanguard: "Vanguard", cavalry: "Cavalry", range: "Range", unique: "Unique", mountain: "Mountain" }

// Every unit's hex carries a faint rim of its team's colour from the edge in
// (blue yours, red theirs), the same for every piece: it says whose piece it
// is, nothing more. The pencil skin's parchment disc draws the same colours as
// its own thin rim (game.css --cyvasse-team-1 and --cyvasse-team-0; keep the
// two in step). How much a piece matters now shows in the size of its art
// (units.js sizeTier, scaled in game.css); the rim no longer deepens with the
// piece's worth (Alex, September 29, 2026).
const TEAM_SHADE = { 1: "#3b82f6", 0: "#dc2626" }
const SHADE_STOPS = [["58%", 0], ["100%", 0.45]]
// The glow of the last move and of the selection: [offset, colour, opacity]
// from the centre out. The last move's fades away; the selection's pulses.
// Warm and strongest at the centre, easing off towards the edge, where a
// moved unit's team rim shows through (the in-danger glow runs the other
// way, orange from the edges in, and pulses).
const HEX_GLOW = [["0%", "#ffd27f", 0.72], ["45%", "#ffb04a", 0.5], ["80%", "#ff9a1f", 0.3], ["100%", "#ff8c1a", 0.22]]

// The board key (games/_threat_toggle) counts as a control: reading it keeps the picked piece.
const CONTROLS = "button, a, input, label, select, textarea, summary, [role=button], .cyvasse-legend"

export default class extends Controller {
  static targets = ["board", "banner", "status", "dock", "setupControls", "startButton", "info", "graveyard", "opponent", "hint", "threatToggle",
    "army", "smartButton", "armyCount", "armyClock", "armyStatus", "fallen"]
  static values = { skin: { type: String, default: "vector" }, images: Object, skins: Object, pace: { type: Number, default: 1 } }

  connect() {
    this.timers = new Set()
    this.buildBoard()
    this.newGame()
  }

  disconnect() {
    this.lastMoveMarker?.stop()
    this.dockObserver?.disconnect()
    clearTimeout(this.setupFitTimer)
    this.cursorEvents?.abort()
    this.clearTimers()
    this.bannerBox.hide()
  }

  // ---- Game lifecycle ------------------------------------------------------

  newGame() {
    this.clearTimers()
    this.game = new Game()
    this.announcedLineup = undefined
    this.pendingJump = null
    this.holding = false
    this.selectedUnitId = null
    this.selectedHex = null
    this.actions = null
    this.notice = null
    this.opponentTarget.textContent = this.game.computer.name
    this.setupControlsTarget.hidden = false
    this.hideBanner()
    this.render()
    this.setupBoardShown = false
    this.showBoardWhenSetupOpens()
  }

  // "✨ Smart Setup", "✨ Place All", "✨ New Setup" (cyvasse/smart_setup):
  // one of the strategic openings, not one of this browser's last ten picks,
  // around whatever the player has already placed.
  smartSetup() {
    if (this.game.phase !== "setup") return
    this.recentSetups ??= recentPicks()
    const { opening, lineup } = smartLineup(this.game.teamUnits(PLAYER), { recent: this.recentSetups })
    this.game.loadLineup(lineup)
    this.recentSetups = rememberPick(this.recentSetups, opening.slug)
    this.clearSelection()
    this.render()
  }

  // Saved lineups (cyvasse-setups, setups/_panel): place one, or hand over
  // the army on the board to be saved. `loaded` tells the panel it took.
  loadLineup(event) {
    if (this.game.phase !== "setup") return
    try {
      this.game.loadLineup(event.detail.lineup)
    } catch {
      return
    }
    event.detail.loaded = true
    this.selectedUnitId = null
    this.render()
  }

  collectLineup(event) {
    if (this.game.readyToStart) event.detail.lineup = this.game.playerLineup()
  }

  start() {
    if (!this.game.readyToStart) return
    this.game.start()
    this.emailGoal("played_match")
    // Hold the board until the opening banner hands over to turn 1: a move
    // made under the banner would start a second turn loop when it closes.
    this.holding = true
    this.element.dataset.holding = "true"
    this.selectedUnitId = null
    this.setupControlsTarget.hidden = true
    this.render()
    const first = this.game.offense === PLAYER ? "You have the first move." : "Opponent has the first move."
    this.banner(first, () => this.runTurn())
  }

  // Game.runTurn: announce the turn, mark the last move, let the computer think.
  // `result` is what Game#act answered for the turn just played; when the
  // side after it had no legal move, its turn passed (the stalemate rule), and
  // the player is told who passed.
  runTurn(result = {}) {
    this.holding = false
    this.clearSelection()
    const passed = result.passed && this.game.phase !== "over"
    this.notice = passed ? passNotice(1 - this.game.offense, this.game.computer.name) : null
    this.render()
    if (this.game.phase === "over") return this.announceWinner()

    const whose = this.game.offense === PLAYER ? "Your move" : "Opponent’s move"
    this.banner(`${passed ? (this.game.offense === PLAYER ? "Opponent passes · " : "You pass · ") : ""}Turn ${fullMove(this.game.turn)} · ${whose}`)
    if (this.game.offense === COMPUTER) this.computerTurn()
  }

  // The computer's rhythm (cyvasse/pacing): select its unit after 2-5 s, move
  // it 3-5 s later, and a cavalry unit's second jump 2-3 s after that.
  computerTurn() {
    const action = chooseAction(this.game)
    if (!action) return
    const delays = botDelays()
    this.later(delays.select, () => {
      this.select(action.from)
      this.later(delays.move, () => {
        const result = this.game.act(action.from, action.to)
        if (result.secondJump) {
          this.select(this.game.activeHex)
          this.later(delays.second, () => {
            const next = chooseAction(this.game)
            this.runTurn(this.game.act(next.from, next.to))
          })
        } else {
          this.runTurn(result)
        }
      })
    })
  }

  announceWinner() {
    if (this.game.winner === null) return this.banner("Neither side can move. A draw.", null, { stay: true })
    const turn = fullMove(this.game.turn)
    const text = this.game.winner === PLAYER ? `You win, at turn ${turn}.` : `You were defeated, at turn ${turn}.`
    this.banner(text, null, { stay: true })
  }

  // A player who came from an email: tell the hub's email analytics this
  // result happened (EmailReferral). The meta tag is there only for them.
  emailGoal(goal) {
    const url = document.querySelector("meta[name='email-goal-url']")?.content
    if (!url) return
    const beacon = new Image()
    beacon.src = url + goal
    this.emailBeacon = beacon
  }

  // ---- Clicks --------------------------------------------------------------

  clickHex(event) {
    if (this.holding) return
    const node = event.target.closest("[data-hex]")
    const hex = node ? Number(node.dataset.hex) : null
    if (this.game.phase === "setup") return this.setupClick(hex)
    if (this.game.phase === "play" && this.game.offense === PLAYER) this.playClick(hex)
  }

  // A click anywhere off the board lets go of the picked piece; controls
  // (the dock, buttons, links, form fields) keep it.
  clickAway(event) {
    const path = event.composedPath()
    if (!this.game || this.holding || path.includes(this.boardTarget)) return
    if (path.some((node) => node.matches?.(CONTROLS))) return
    if (this.game.phase === "setup") return this.setupClick(null)
    if (this.game.phase === "play" && this.game.offense === PLAYER) this.playClick(null)
  }

  // Keyboard play: the board is one tab stop. Arrows move between hexes
  // (up and down to the nearest hex in the next row), Enter or Space clicks.
  keyHex(event) {
    const node = event.target.closest("[data-hex]")
    if (!node) return
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      return this.clickHex(event)
    }
    const next = this.neighbourFor(Number(node.dataset.hex), event.key)
    if (!next) return
    event.preventDefault()
    this.focusHex(next)
  }

  neighbourFor(index, key) {
    const here = this.hexCentres.get(index)
    const row = { ArrowUp: here.row - 1, ArrowDown: here.row + 1 }[key]
    if (key === "ArrowLeft" || key === "ArrowRight") {
      const next = index + (key === "ArrowLeft" ? -1 : 1)
      return this.hexCentres.get(next)?.row === here.row ? next : null
    }
    if (row === undefined) return null
    let best = null
    for (const [i, centre] of this.hexCentres) {
      if (centre.row !== row) continue
      if (best === null || Math.abs(centre.x - here.x) < Math.abs(this.hexCentres.get(best).x - here.x)) best = i
    }
    return best
  }

  focusHex(index) {
    for (const [i, { group }] of this.hexNodes) group.setAttribute("tabindex", i === index ? "0" : "-1")
    this.hexNodes.get(index).group.focus()
  }

  pickFromDock(event) {
    if (this.game.phase !== "setup") return
    this.selectedUnitId = event.currentTarget.dataset.unitId
    this.render()
    this.showBoardForSetup()
  }

  // ---- The setup layouts (game.css, "setup layouts") ------------------------
  // Under 1024px the army card is a sheet fixed to the screen during setup:
  // at the bottom held upright, at the right on its side. The bottom sheet's
  // measured height (--dock-sheet) pads the page, so the panel under the
  // board scrolls clear of it, and caps the board, so it fits above it.

  watchDock() {
    this.dockObserver?.disconnect()
    if (!this.hasArmyTarget || !window.ResizeObserver) return
    this.dockObserver = new ResizeObserver(() => this.measureDock())
    this.dockObserver.observe(this.armyTarget)
  }

  // Which fit the screen's setup layout keeps (game.css --setup-fit):
  // "bottom", "side", "page", or "" (a desktop, which needs no help).
  get setupFit() {
    return getComputedStyle(this.element).getPropertyValue("--setup-fit").trim()
  }

  measureDock() {
    const bottom = this.hasArmyTarget && this.setupFit === "bottom"
    const height = bottom ? Math.ceil(this.armyTarget.getBoundingClientRect().height) : 0
    if (height > 0) this.element.style.setProperty("--dock-sheet", `${height}px`)
    else this.element.style.removeProperty("--dock-sheet")
  }

  // Setup opening: on a phone the player's own five rows are the board's
  // bottom, off the screen or under the sheet until the page scrolls. Bring
  // the board into view once, as a pick does, after the sheet has laid out,
  // so those rows are in view before the first pick.
  showBoardWhenSetupOpens() {
    if (this.setupControlsTarget.hidden || this.setupBoardShown) return
    this.setupBoardShown = true
    requestAnimationFrame(() => {
      this.measureDock()
      this.showBoardForSetup()
    })
  }

  // A unit picked from the army card: scroll once so the whole board is on
  // the screen under the pinned navbar: above a bottom sheet, beside a side
  // sheet, or (a tablet on its side, "page") with the army card beside it,
  // both in the page. Every placement after needs no scrolling. By hand, not
  // scrollIntoView: the page's root clips sideways (overflow-x: clip), and
  // Chrome then scrolls it into view not at all.
  //
  // The scroll collapses the pinned navbar, which then lifts the page under
  // it by the height it lost; with a board capped close to the screen's
  // height (a phone on its side), that can lift the board's top under the
  // navbar. So once the scroll and the collapse have settled, one more pass
  // puts it right; it moves nothing when the board already fits.
  showBoardForSetup({ recheck = true } = {}) {
    const fit = this.hasArmyTarget ? this.setupFit : ""
    if (!fit) return
    const by = setupScrollBy({
      fit,
      board: this.boardTarget.getBoundingClientRect(),
      army: this.armyTarget.getBoundingClientRect(),
      pinned: parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--pin-stack-bottom")) || 0,
      viewportHeight: window.innerHeight
    })
    if (!by) return
    const still = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
    window.scrollBy({ top: by, behavior: still ? "auto" : "smooth" })
    if (!recheck) return
    clearTimeout(this.setupFitTimer)
    this.setupFitTimer = setTimeout(() => this.showBoardForSetup({ recheck: false }), still ? 300 : 700)
  }

  setupClick(hex) {
    const unit = hex == null ? null : this.game.pieceAt(hex)
    const intent = setupIntent({ hex, unit, selectedUnitId: this.selectedUnitId })
    if (intent === "none") return
    if (intent === "select") {
      this.selectedUnitId = unit.id
    } else if (intent === "place") {
      this.game.place(this.selectedUnitId, hex)
      this.selectedUnitId = null
    } else {
      this.selectedUnitId = null
    }
    this.render()
  }

  intentFor(hex) {
    return playIntent({ hex, selectedHex: this.selectedHex, actions: this.actions, selectable: this.game.selectableHexes() })
  }

  deselect() {
    this.clearSelection()
    this.render()
  }

  playClick(hex) {
    const intent = this.intentFor(hex)
    if (intent === "deselect") return this.deselect()
    if (intent === "act") {
      const before = this.game.jump === 1 ? this.game.snapshot() : null
      const result = this.game.act(this.selectedHex, hex)
      this.pendingJump = result.secondJump ? before : null
      if (result.secondJump) {
        this.render()
        this.select(this.game.activeHex)
      } else {
        this.runTurn(result)
      }
      return
    }
    if (intent === "select") this.select(hex)
  }

  // "Start over" (Esc, or the hint's button on touch): let go of the picked
  // piece. Midway through a cavalry double jump, before the turn is played,
  // it takes the first jump back, so the horse can move again from where it
  // stood. In setup it puts a picked unit back down.
  startOver(event) {
    if (event?.type === "keydown" && event.target.closest?.("input, textarea, select, [contenteditable]")) return
    if (this.holding || !this.game) return
    const game = this.game
    if (game.phase === "setup") {
      if (!this.selectedUnitId) return
      this.selectedUnitId = null
      return this.render()
    }
    if (game.phase !== "play") return
    if (this.pendingJump && game.jump === 2) {
      game.restoreSnapshot(this.pendingJump)
      this.pendingJump = null
      this.steps = []
    } else if (this.selectedHex == null) {
      return
    }
    this.clearSelection()
    this.render()
  }

  toggleThreats(event) {
    const { threatGroup } = event.target.dataset
    this.showThreats[threatGroup] = event.target.checked
    try {
      window.localStorage.setItem(`${THREATS_KEY}.${threatGroup}`, event.target.checked ? "on" : "off")
    } catch {
      // Storage refused (a private window): the switch still works this visit.
    }
    this.renderThreats()
  }

  // ---- Drawing -------------------------------------------------------------

  buildBoard() {
    const width = 11 * W + PAD * 2
    const height = 10 * H * 0.75 + H + PAD * 2
    const svg = this.boardTarget
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`)
    svg.replaceChildren()
    const defs = el("defs", {})
    for (const [team, color] of Object.entries(TEAM_SHADE)) {
      const gradient = el("radialGradient", { id: `shade-${team}`, r: "60%" })
      for (const [offset, opacity] of SHADE_STOPS) {
        gradient.append(el("stop", { offset, "stop-color": color, "stop-opacity": opacity }))
      }
      defs.append(gradient)
    }
    for (const hue of new Set(Object.values(MOVE_HUE))) {
      for (const [table, entries] of Object.entries(HSL_TABLES)) {
        entries.forEach((entry, step) => {
          const gradient = el("radialGradient", { id: `ring-${hue}-${table}-${step}`, cx: "50%", cy: "46%", r: "62%", fx: "42%", fy: "34%" })
          for (const [offset, color] of ringStops(hue, entry)) gradient.append(el("stop", { offset, "stop-color": color }))
          defs.append(gradient)
        })
      }
    }
    const gradientOf = (id, stops) => {
      const gradient = el("radialGradient", { id, cx: "50%", cy: "46%", r: "62%", fx: "42%", fy: "34%" })
      for (const [offset, color, opacity = 1] of stops) {
        gradient.append(el("stop", { offset, "stop-color": opacity < 1 ? overBoard(color, opacity) : color }))
      }
      defs.append(gradient)
    }
    for (const [id, stops] of Object.entries(GROUND)) gradientOf(id, stops)
    for (const [table, entries] of Object.entries(HSL_TABLES)) {
      entries.forEach((entry, step) => {
        for (const hue of Object.values(PREVIEW_HUE)) gradientOf(`ghost-${hue}-${table}-${step}`, ghostStops(hue, entry))
        gradientOf(`sunken-${table}-${step}`, sunkenStops(entry))
        const [s, l] = entry.split(",").map((part) => parseFloat(part))
        for (const [kind, stops] of Object.entries(RANGE_STOPS)) gradientOf(`${kind}-${table}-${step}`, stops(s, l))
      })
    }
    // A unit in danger: orange from the hex's edges in, like the team shade.
    const danger = el("radialGradient", { id: "danger-edge", r: "60%" })
    for (const [offset, opacity] of [["35%", 0], ["100%", 1]]) {
      danger.append(el("stop", { offset, "stop-color": "#f97316", "stop-opacity": opacity }))
    }
    defs.append(danger)
    // The last move and the selection: a soft orange glow from the centre
    // (HEX_GLOW). The last move's fades away, the selection's pulses
    // (game.css .hex-glow).
    const glow = el("radialGradient", { id: "hex-glow", r: "58%" })
    for (const [offset, color, opacity] of HEX_GLOW) {
      glow.append(el("stop", { offset, "stop-color": color, "stop-opacity": opacity }))
    }
    defs.append(glow)
    // The texture over a lit hex: a fine diagonal hatch, light and faint.
    const texture = el("pattern", { id: "ring-texture", patternUnits: "userSpaceOnUse", width: 5, height: 5, patternTransform: "rotate(40)" })
    texture.append(el("line", { x1: 0, y1: 0, x2: 0, y2: 5, stroke: "white", "stroke-opacity": 0.14, "stroke-width": 1.2 }))
    texture.append(el("line", { x1: 2.5, y1: 0, x2: 2.5, y2: 5, stroke: "black", "stroke-opacity": 0.1, "stroke-width": 0.8 }))
    defs.append(texture)
    svg.append(defs)
    this.hexNodes = new Map()
    this.hexCentres = new Map()

    const FULL = hexCorners(W, H)
    const cornersAt = (scale) => pointsAttribute(hexCorners(W, H, scale))
    const corners = cornersAt(0.97)
    // Inset, inside the band a highlight edge draws over.
    const dangerCorners = cornersAt(0.935)
    // The art, and the pencil skin's parchment disc, stand on their hex
    // (cyvasse/art_clip): cut along its right, lower-right and lower-left
    // outline, free to rise over the hexes behind it, up and to the left.
    // The paint order does the rest: hexes draw in reading order, rows top to
    // bottom and each row left to right, so a piece's art covers the hexes
    // behind it and the hexes in front of it cover nothing of it (the clip
    // keeps it off them). Every highlight border, the threat outline among
    // them, draws after every hex (.hex-edges below), over all the art.
    const artClip = el("clipPath", { id: "hex-art-clip" })
    artClip.append(el("polygon", { points: pointsAttribute(artClipCorners(W, H, { scale: 0.97 })) }))
    defs.append(artClip)

    for (const hex of HEXES) {
      const cx = PAD + (11 - hex.size) * W / 2 + (hex.x - 0.5) * W
      const cy = PAD + H / 2 + (hex.y - 1) * H * 0.75
      const group = el("g", {
        class: "hex", "data-hex": hex.index, role: "button", tabindex: hex.index === 1 ? "0" : "-1",
        transform: `translate(${cx.toFixed(2)} ${cy.toFixed(2)})`
      })
      const polygon = el("polygon", { class: "hex-poly", points: corners })
      const texture = el("polygon", { class: "ring-texture", points: corners, fill: "url(#ring-texture)" })
      const shade = el("polygon", { class: "unit-shade", points: corners })
      const glow = el("polygon", { class: "hex-glow", points: corners, fill: "url(#hex-glow)" })
      const danger = el("polygon", { class: "danger-edge", points: dangerCorners, fill: "url(#danger-edge)" })
      // The pencil skin's glow ring (game.css .unit-ring): under the disc,
      // showing only outside the disc's own team rim.
      const ring = el("circle", { class: "unit-ring", r: 27 })
      const disc = el("circle", { class: "unit-disc", r: 27 })
      const image = el("image", { class: "unit-image", x: -28, y: -30, width: 56, height: 60 })
      const art = el("g", { class: "unit-art", "clip-path": "url(#hex-art-clip)" })
      art.append(ring, disc, image)
      group.append(polygon, texture, shade, glow, danger, art)
      svg.append(group)
      this.hexNodes.set(hex.index, { group, polygon, shade, glow, disc, ring, image })
      this.hexCentres.set(hex.index, { x: cx, y: cy, row: hex.y })
    }

    // Every highlight border, one line per edge on the line two hexes share,
    // wide enough to cover both their edges (renderEdges gives it an owner).
    const edges = el("g", { class: "hex-edges" })
    this.edgeLines = new Map()
    for (const { key, hex, side, other } of EDGES) {
      const { x, y } = this.hexCentres.get(hex)
      const [ax, ay] = FULL[side]
      const [bx, by] = FULL[(side + 1) % 6]
      const line = el("line", {
        class: "hex-edge", "data-edge": key, "data-between": `${hex} ${other ?? "rim"}`,
        x1: (x + ax).toFixed(2), y1: (y + ay).toFixed(2), x2: (x + bx).toFixed(2), y2: (y + by).toFixed(2)
      })
      edges.append(line)
      this.edgeLines.set(key, line)
    }
    // Hover and keyboard focus, drawn over every border (moveCursor).
    this.hoverCursor = el("polygon", { class: "hex-cursor", points: corners })
    this.focusCursor = el("polygon", { class: "hex-cursor is-focus", points: corners })
    svg.append(edges, this.hoverCursor, this.focusCursor)
    this.cursorEvents?.abort()
    this.cursorEvents = new AbortController()
    const on = (type, fn) => svg.addEventListener(type, fn, { signal: this.cursorEvents.signal })
    on("pointerover", (e) => { if (e.pointerType !== "touch") this.moveCursor(this.hoverCursor, e.target.closest?.("[data-hex]")) })
    on("pointerleave", () => this.moveCursor(this.hoverCursor, null))
    on("focusin", (e) => this.moveCursor(this.focusCursor, e.target.matches?.(":focus-visible") ? e.target.closest("[data-hex]") : null))
    on("focusout", () => this.moveCursor(this.focusCursor, null))
    this.watchDock()

    // What a screen reader says after a threatened unit's name (renderThreats).
    // Hidden text, joined to the name with aria-labelledby (which reads hidden
    // nodes), because Safari's VoiceOver reads aria-description only in part.
    // Hidden, not just off screen, so browse mode never reads it on its own.
    const noteId = `${this.identifier}-danger-note`
    this.dangerNote = document.getElementById(noteId) ?? document.createElement("span")
    this.dangerNote.id = noteId
    this.dangerNote.hidden = true
    this.dangerNote.textContent = "In danger: the opponent can take it next turn"
    if (!this.dangerNote.isConnected) svg.after(this.dangerNote)
  }

  // ---- Piece skin ------------------------------------------------------------

  // The skin switcher's forms (skins/_toggle) submit here. The choice is saved
  // first (PATCH /skin), and the board changes art only once the server has
  // said yes; the game in progress is kept. If the save fails, the form is
  // posted the ordinary way, which reloads /play in whatever the server holds.
  async switchSkin(event) {
    event.preventDefault()
    const form = event.target
    const skin = form.dataset.skinChoice
    // One switch at a time: a second click while the first is saving could
    // land its answers out of order and leave the board in one skin while
    // the server holds the other.
    if (this.switchingSkin || !this.skinsValue[skin] || skin === this.skinValue) return

    this.switchingSkin = true
    // Disabling the focused button drops focus to <body>; put it back after.
    const focused = document.activeElement
    const buttons = this.element.querySelectorAll(".skin-choice")
    for (const button of buttons) button.disabled = true
    let response = null
    try {
      response = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
    } catch {
      response = null
    } finally {
      this.switchingSkin = false
      for (const button of buttons) button.disabled = false
      if (focused?.isConnected && document.activeElement !== focused) focused.focus()
    }
    if (!response?.ok) return form.submit()
    this.applySkin(skin)
  }

  applySkin(skin) {
    this.skinValue = skin
    this.imagesValue = this.skinsValue[skin]
    this.element.dataset.skin = skin
    for (const button of this.element.querySelectorAll(".skin-choice")) {
      button.setAttribute("aria-pressed", String(button.dataset.skin === skin))
    }
    // Repaint only the art: a full render() would drop the move and attack
    // rings of a unit the player has selected.
    for (const [index, node] of this.hexNodes) {
      const unit = this.game.pieceAt(index)
      if (unit) node.image.setAttribute("href", this.imagesValue[unit.type.codename])
    }
    this.renderDock()
    this.renderGraveyards()
    this.renderInfo(this.selectedUnitId ? this.game.unit(this.selectedUnitId) : null)
  }

  render() {
    const game = this.game
    const root = this.element
    root.dataset.phase = game.phase
    root.dataset.turn = game.turn
    root.dataset.offense = game.offense ?? ""
    root.dataset.holding = this.holding ? "true" : "false"

    for (const [index, node] of this.hexNodes) {
      const unit = game.pieceAt(index)
      node.group.classList.toggle("has-unit", !!unit)
      node.group.classList.remove("is-move", "is-attack", "is-selected", "is-deploy", "is-drop", "is-last-move", ...RING_CLASSES)
      delete node.group.dataset.ghost
      node.group.dataset.unitId = unit?.id ?? ""
      node.group.dataset.team = unit ? unit.team : ""
      if (unit) {
        node.group.dataset.unit = unit.type.codename
        node.group.dataset.tier = unit.type.sizeTier
        node.shade.setAttribute("fill", `url(#shade-${unit.team})`)
      } else {
        delete node.group.dataset.unit
        delete node.group.dataset.tier
        node.shade.removeAttribute("fill")
      }
      if (unit) {
        node.image.setAttribute("href", this.imagesValue[unit.type.codename])
      } else {
        node.image.removeAttribute("href")
      }
      node.polygon.style.fill = ""
    }

    if (game.phase === "setup") {
      for (const [index, node] of this.hexNodes) {
        if (inPlayerZone(index)) node.group.classList.add("is-deploy")
      }
      const selected = this.selectedUnitId && game.unit(this.selectedUnitId)
      if (selected?.hex) this.hexNodes.get(selected.hex).group.classList.add("is-selected")
      // A picked unit lights the empty hexes of your rows it may go to.
      if (selected) {
        for (const [index, node] of this.hexNodes) {
          if (inPlayerZone(index) && !game.pieceAt(index)) node.group.classList.add("is-drop")
        }
      }
    }
    this.markLastMove()

    this.paintGround()
    this.labelHexes()
    this.renderThreats()
    this.renderHint()
    this.renderDock()
    this.renderStatus()
    this.renderGraveyards()
    this.renderInfo(this.selectedUnitId ? game.unit(this.selectedUnitId) : null)
    this.announceLineup()
  }

  // The setup panel's opening picker (cyvasse-openings#reflect) names the
  // army on the board: the whole lineup string, or null while any unit is
  // still in the dock. Sent only when it changes, not on every redraw.
  announceLineup() {
    if (this.game.phase !== "setup") return
    const lineup = this.game.readyToStart ? this.game.playerLineup() : null
    if (lineup === this.announcedLineup) return
    this.announcedLineup = lineup
    this.dispatch("lineup", { detail: { lineup } })
  }

  // The last move glows until ten seconds after it landed. A redraw partway
  // through sets the fade's clock back by the time already run (a negative
  // animation-delay), so the glow carries on rather than starting over.
  markLastMove() {
    const game = this.game
    // Made here, not in connect(): the match board has its own connect().
    this.lastMoveMarker ??= new LastMoveMarker({ onExpire: () => this.clearLastMove() })
    const moved = game.phase === "setup" ? [] : [...game.lastMove, game.utilMove].filter((hex) => hex != null)
    const { hexes, elapsed } = this.lastMoveMarker.mark(game.phase === "setup" ? "" : lastMoveKey(game), moved)
    this.boardTarget.style.setProperty("--last-move-delay", `${-elapsed}ms`)
    for (const hex of hexes) {
      const node = this.hexNodes.get(hex)
      if (!node) continue
      node.group.classList.add("is-last-move")
      // render() takes the class off and puts it back in one pass, so a fade
      // already running keeps its start time; the new delay would then count
      // the elapsed time twice and jump the glow ahead. Start it over, so the
      // delay alone sets how far through it is. The pencil skin's glow ring
      // (game.css .unit-ring, cyvasse-last-move-rim) runs on the same clock.
      for (const fade of [node.glow, node.ring].flatMap((layer) => layer.getAnimations?.() ?? [])) {
        if (fade.animationName?.startsWith("cyvasse-last-move")) { fade.cancel(); fade.play() }
      }
    }
  }

  clearLastMove() {
    for (const { group } of this.hexNodes.values()) group.classList.remove("is-last-move")
  }

  // Each hex's aria-label (cyvasse/hex_label): what stands on it, and while a
  // unit of the player's is picked, what a click there would do. The picked
  // unit's hex is aria-pressed; no other hex carries the attribute. Keyboard
  // play hears the board this way; the status line says what was picked.
  labelHexes() {
    const game = this.game
    const pieceAt = (index) => game.pieceAt(index)
    let states
    if (game.phase === "setup") {
      const selected = this.selectedUnitId && game.unit(this.selectedUnitId)
      const drops = [...this.hexNodes].filter(([, { group }]) => group.classList.contains("is-drop")).map(([index]) => index)
      states = selected ? hexStates({ dropHexes: drops, selectedHex: selected.hex ?? null }) : new Map()
    } else {
      states = hexStates({ hexes: this.hexNodes.keys(), pieceAt, selectedHex: this.selectedHex, actions: this.actions })
    }
    for (const [index, { group }] of this.hexNodes) {
      const state = states.get(index)
      const label = hexLabel(index, pieceAt(index), state)
      if (group.getAttribute("aria-label") !== label) group.setAttribute("aria-label", label)
      if (state === "selected") group.setAttribute("aria-pressed", "true")
      else group.removeAttribute("aria-pressed")
    }
  }

  // The status line's word on the player's picked unit, or "" (selectionNote).
  pickedNote() {
    if (this.selectedHex == null || !this.actions) return ""
    const unit = this.game.pieceAt(this.selectedHex)
    return unit?.team === PLAYER ? selectionNote(unit, this.actions) : ""
  }

  // The status line is the board's one live region: write it only on a
  // change, so a redraw that says the same thing is not read out again. A
  // match's army card shows a copy for the eye (armyStatus, aria-hidden)
  // while the line itself is read, not shown (task cyvasse-sidebar-reorder).
  // `shown` is what that copy says, when it should say less than is read.
  setStatus(text, shown = text) {
    if (this.statusTarget.textContent !== text) this.statusTarget.textContent = text
    if (this.hasArmyStatusTarget && this.armyStatusTarget.textContent !== shown) this.armyStatusTarget.textContent = shown
  }

  // Each hex's resting fill, from the classes render() just set. It is the
  // polygon's fill attribute, so the stylesheet's orange (the selection) and a
  // ring's inline gradient both draw over it.
  paintGround() {
    for (const { group, polygon } of this.hexNodes.values()) {
      const ground = group.classList.contains("is-drop") ? "hex-drop" : group.classList.contains("is-deploy") ? "hex-deploy" : "hex-base"
      polygon.setAttribute("fill", `url(#${ground})`)
    }
  }

  // Where the opponent could strike next turn (cyvasse/threats, from the
  // rules' own legal actions): each hex in reach gets .is-threatened, and
  // renderEdges outlines the switched-on groups' area (their units counted in,
  // so it is one shape) in red, by cyvasse/edges PERIMETER_STYLE; each unit of yours
  // they could actually kill gets .is-danger (the orange edge pulse). Play
  // only; the ranged and melee switches each turn off their own group.
  renderThreats() {
    const game = this.game
    // Read once per page, by /play and the match board alike.
    this.showThreats ??= Object.fromEntries(THREAT_GROUPS.map((group) => [group, threatsWanted(group)]))
    const groups = THREAT_GROUPS.filter((group) => this.showThreats[group])
    const live = game.phase === "play" && groups.length > 0
    for (const input of this.threatToggleTargets) {
      input.checked = this.showThreats[input.dataset.threatGroup]
      input.closest(".cyvasse-threat-toggles").hidden = game.phase !== "play"
    }
    const reach = new Set()
    const kills = new Set()
    this.threatRegions = {}
    for (const group of THREAT_GROUPS) {
      const region = new Set()
      if (live && this.showThreats[group]) {
        const found = threats(game, 1 - PLAYER, { groups: [group] })
        for (const hex of found.reach) {
          reach.add(hex)
          region.add(hex)
        }
        for (const hex of found.kills) kills.add(hex)
        for (const hex of found.units) region.add(hex)
      }
      this.threatRegions[group] = region
    }
    this.threatRims = threatRims(this.threatRegions, this.perimeterStyle ?? PERIMETER_STYLE)
    for (const [index, node] of this.hexNodes) {
      const unit = game.pieceAt(index)
      const danger = kills.has(index) && unit?.team === PLAYER
      node.group.classList.toggle("is-danger", danger)
      node.group.classList.toggle("is-threatened", reach.has(index))
      // Said after the unit's name (its own aria-label, which stays as it is),
      // from the visually hidden note buildBoard made.
      if (danger) {
        node.group.id ||= `${this.identifier}-hex-${index}`
        node.group.setAttribute("aria-labelledby", `${node.group.id} ${this.dangerNote.id}`)
      } else {
        node.group.removeAttribute("aria-labelledby")
      }
    }
    this.renderEdges()
  }

  // Each edge drawn once, in the colour of the highest highlight on either
  // side (cyvasse/edges EDGE_PRIORITY). Runs per render and ripple step only.
  renderEdges() {
    if (!this.edgeLines) return
    const claims = new Map()
    for (const [index, { group }] of this.hexNodes) {
      const kind = hexClaim(new Set(group.classList), { ghost: group.dataset.ghost })
      if (kind) claims.set(index, kind)
    }
    const owners = resolveEdges(claims, this.threatRims?.solid, this.threatRims?.dashed)
    for (const [key, line] of this.edgeLines) {
      const kind = owners.get(key)
      // Only on a change, so the danger pulse is not restarted.
      if (line.dataset.kind === kind) continue
      if (kind) line.dataset.kind = kind
      else delete line.dataset.kind
    }
  }

  moveCursor(cursor, group) {
    cursor.classList.toggle("is-on", !!group)
    if (group) cursor.setAttribute("transform", group.getAttribute("transform"))
  }

  // The "start over" hint shows while there is something to start over from.
  renderHint() {
    if (!this.hasHintTarget) return
    const game = this.game
    const picked = game.phase === "setup" ? !!this.selectedUnitId
      : game.phase === "play" && (this.selectedHex != null || (!!this.pendingJump && game.jump === 2))
    this.hintTarget.hidden = !picked || this.holding
  }

  // Every unit keeps its slot: a placed one leaves an empty .dock-slot, so
  // the dock, and Ready under it, never change size or move.
  renderDock() {
    const army = this.game.teamUnits(PLAYER)
    const placed = army.filter((unit) => unit.status !== "unplaced").length
    this.dockTarget.replaceChildren(...army.map((unit) => {
      if (unit.status !== "unplaced") {
        const slot = document.createElement("span")
        slot.className = "dock-slot"
        slot.setAttribute("aria-hidden", "true")
        return slot
      }
      const button = document.createElement("button")
      button.type = "button"
      button.className = "dock-unit"
      button.dataset.unitId = unit.id
      button.dataset.action = `${this.identifier}#pickFromDock`
      button.setAttribute("aria-pressed", unit.id === this.selectedUnitId)
      button.setAttribute("aria-label", unit.type.name)
      button.append(img(this.imagesValue[unit.type.codename], unit.type.name))
      return button
    }))
    this.startButtonTarget.disabled = !this.game.readyToStart
    if (!this.hasArmyTarget) return
    const mode = smartSetupMode(placed, army.length)
    this.armyTarget.dataset.armyMode = mode
    // Only on a change, so a render that moves nothing leaves the DOM alone.
    // The count is for the eye: renderStatus speaks it through the one live
    // region, so a placement is announced once.
    const label = this.smartButtonTarget.querySelector("[data-smart-label]") ?? this.smartButtonTarget
    const count = placed < army.length ? `${placed} of ${army.length} placed` : `All ${army.length} placed`
    if (label.textContent !== SMART_LABELS[mode]) label.textContent = SMART_LABELS[mode]
    if (this.armyCountTarget.textContent !== count) this.armyCountTarget.textContent = count
  }

  renderStatus() {
    const game = this.game
    let text
    if (game.phase === "setup") {
      const army = game.teamUnits(PLAYER)
      const placed = army.filter((unit) => unit.status !== "unplaced").length
      text = placed < army.length ? `Place your army: ${placed} of ${army.length} placed.` : "Your army is in place. Press Ready."
    } else if (game.phase === "over") {
      text = game.winner === PLAYER ? "You win." : game.winner === COMPUTER ? "You were defeated." : "A draw."
    } else if (game.offense === PLAYER) {
      const turn = fullMove(game.turn)
      text = game.jump === 2 ? `Turn ${turn}: your cavalry jumps again.` : `Turn ${turn}: your move.`
      const picked = this.pickedNote()
      if (picked) text = `${text} ${picked}`
    } else {
      text = `Turn ${fullMove(game.turn)}: the opponent is thinking.`
    }
    this.setStatus(this.notice && game.phase === "play" ? `${this.notice} ${text}` : text)
  }

  // The fallen card stays hidden until a unit of either side falls.
  renderGraveyards() {
    let fallen = 0
    for (const target of this.graveyardTargets) {
      const dead = this.game.graveyard(Number(target.dataset.team))
      fallen += dead.length
      target.replaceChildren(...dead.map((u) => img(this.imagesValue[u.type.codename], u.type.name)))
    }
    if (this.hasFallenTarget) this.fallenTarget.hidden = fallen === 0
  }

  // The selected-unit box (infoBoxes.js InfoBox.update).
  renderInfo(unit) {
    const box = this.infoTarget
    if (!unit) {
      box.hidden = true
      return
    }
    const type = unit.type
    const rows = [["Class", RANK_LABEL[type.rank]]]
    if (type.codename === "mountain") {
      rows.push(["Strength", "Impassable"])
    } else {
      rows.push(["Strength", type.attack])
      const movement = type.codename === "dragon" ? "Straight line" : type.rank === "cavalry" ? `${type.moveRange} + ${type.secondJump}` : type.moveRange
      rows.push(["Movement", movement])
      if (type.rank === "range") rows.push(["Range", type.attackRange])
    }
    box.hidden = false
    box.querySelector("[data-info=name]").textContent = type.name
    box.querySelector("[data-info=image]").replaceChildren(img(this.imagesValue[type.codename], type.name))
    box.querySelector("[data-info=stats]").replaceChildren(...rows.map(([key, value]) => {
      const row = document.createElement("div")
      const dt = document.createElement("dt")
      const dd = document.createElement("dd")
      dt.textContent = key
      dd.textContent = value
      row.append(dt, dd)
      return row
    }))
    const trumps = box.querySelector("[data-info=trump]")
    trumps.hidden = type.trump.length === 0
    trumps.querySelector("span").replaceChildren(...type.trump.map((codename) => img(this.imagesValue[codename], UNIT_TYPES[codename].name)))
  }

  // ---- Selection and the ring ripple (range.js, animation.js) ---------------

  select(hex) {
    this.clearSelection()
    this.render()
    const unit = this.game.pieceAt(hex)
    this.selectedHex = hex
    this.selectedUnitId = unit.id
    this.actions = this.game.actionsFrom(hex)
    this.renderInfo(unit)

    // Offense.refreshHexVisual: a selection clears the last-move marks.
    for (const { group } of this.hexNodes.values()) group.classList.remove("is-last-move")
    const node = this.hexNodes.get(hex)
    node.group.classList.add("is-selected")
    for (const i of this.actions.moves) this.hexNodes.get(i).group.classList.add("is-move")
    for (const i of this.actions.attacks) this.hexNodes.get(i).group.classList.add("is-attack")
    this.renderEdges()
    this.labelHexes()
    this.ripple(unit)
    this.renderHint()
    this.renderStatus()
  }

  clearSelection() {
    if (this.rippleTimer) clearInterval(this.rippleTimer)
    this.rippleTimer = null
    this.selectedHex = null
    this.selectedUnitId = null
    this.actions = null
  }

  ripple(unit) {
    const type = unit.type
    const table = type.moveRange > 5 ? "long" : "short"
    const { rings, rangeRings, moves } = this.actions
    const shooter = type.rank === "range"
    const reach = shooter ? type.attackRange : type.rank === "cavalry" ? type.moveRange + type.secondJump : type.moveRange
    let distance = 1

    const light = (index, fill, ...classes) => {
      const { group, polygon } = this.hexNodes.get(index)
      polygon.style.fill = fill
      group.classList.remove(...RING_CLASSES)
      group.classList.add(...classes)
      return group
    }

    const paint = () => {
      const step = distance - 1
      for (const [index, ring] of rings) {
        if (ring % 10 !== step || ring < 10) continue
        // A shooter's range owns every hex it cannot move to.
        if (shooter && !moves.includes(index)) continue
        const code = Math.floor(ring / 10)
        if (MOVE_HUE[code] !== undefined) {
          light(index, ringFill(MOVE_HUE[code], table, step), "is-lit")
        } else if (SUNKEN_CODES.has(code)) {
          light(index, `url(#sunken-${table}-${step})`, "is-sunken")
        } else if (PREVIEW_HUE[code] !== undefined) {
          light(index, `url(#ghost-${PREVIEW_HUE[code]}-${table}-${step})`, "is-ghost").dataset.ghost = code
        }
      }
      if (shooter) {
        for (const [index, ring] of rangeRings) {
          if (ring % 10 !== step || ring < 10 || moves.includes(index)) continue
          const kind = RANGE_KIND[Math.floor(ring / 10)]
          if (!kind) continue
          const classes = kind === "field" ? ["is-field", "is-lit"] : [`is-${kind}`]
          light(index, `url(#${kind}-${table}-${step})`, ...classes)
        }
      }
      distance += 1
      this.renderEdges()
    }

    // No ripple for a player who asked for less motion: the rings land at once.
    const still = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
    if (this.paceValue === 0 || still) {
      while (distance <= reach) paint()
      return
    }
    this.rippleTimer = setInterval(() => {
      paint()
      if (distance > reach) {
        clearInterval(this.rippleTimer)
        this.rippleTimer = null
      }
    }, RIPPLE_MS * this.paceValue)
  }

  // ---- The banner (goodCode/rotator.js) --------------------------------------

  banner(text, then = null, options = {}) {
    this.bannerBox.show(text, then, options)
  }

  hideBanner() {
    this.bannerBox.hide()
  }

  get bannerBox() {
    this.bannerInstance ??= new Banner(this.bannerTarget, { pace: () => this.paceValue })
    return this.bannerInstance
  }

  // ---- Timers ------------------------------------------------------------------

  later(ms, fn) {
    const id = setTimeout(() => {
      this.timers.delete(id)
      fn()
    }, ms * this.paceValue)
    this.timers.add(id)
  }

  clearTimers() {
    for (const id of this.timers ?? []) clearTimeout(id)
    this.timers?.clear()
    if (this.rippleTimer) clearInterval(this.rippleTimer)
    this.rippleTimer = null
  }
}

function el(name, attributes) {
  const node = document.createElementNS(SVG_NS, name)
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value)
  return node
}

function img(src, alt) {
  const image = document.createElement("img")
  image.src = src
  image.alt = alt
  return image
}
