import { Controller } from "@hotwired/stimulus"
import { Game, PLAYER, COMPUTER } from "cyvasse/game"
import { chooseAction, KILL_PRIORITY } from "cyvasse/ai"
import { HEXES, hexAt, inPlayerZone } from "cyvasse/board"
import { UNIT_TYPES } from "cyvasse/units"
import { Banner, passNotice } from "cyvasse/banner"
import { threats, outlineEdges } from "cyvasse/threats"

// The Cyvasse board at /play: one game against the computer, in the browser.
//
// The rules live in app/javascript/cyvasse (tested under test/javascript);
// this controller only draws a Game and turns clicks into Game calls. The
// look follows the legacy match screen: black hexes with white edges, orange
// for the last move, and the ring ripple (animation.js) washing out from a
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
// Move ring code -> hue (animation.js updateRing).
const MOVE_HUE = { 1: 240, 2: 290, 3: 10, 4: 10, 5: 280 }

// Each lit hex is filled with a radial gradient rather than the flat legacy
// colour: the ring's own hsl() sits at the middle stop, the centre is lighter
// and the edge deeper, so the hex has depth. The hue drifts a little across
// the hex for colour (blue towards cyan at the centre and indigo at the edge);
// the capture red drifts towards crimson, never towards the selection orange.
// One gradient per hue, table and ripple step, so the outward brightening of
// the ripple still reads. [centre, edge] hue offsets:
const RING_DRIFT = { 240: [-16, 14], 290: [-14, 12], 10: [-4, -18], 280: [-10, 8] }

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
const RING_CLASSES = ["is-lit", "is-ghost", "is-field", "is-target", "is-blocked"]
// The selection, the rings it lights and the last move's orange: the threat
// outline paints beneath these (maskThreats), as it hides nothing a player reads.
const HIGHLIGHTS = ["is-selected", "is-move", "is-attack", "is-last-move", ...RING_CLASSES]

// The threat outline (renderThreats) is on unless the player turned it off.
const THREATS_KEY = "cyvasse.showThreats"

function threatsWanted() {
  try {
    return window.localStorage.getItem(THREATS_KEY) !== "off"
  } catch {
    return true
  }
}

// The six corners of a hex at full size, shared exactly with its neighbours,
// so an edge two threatened hexes share can be found and left undrawn.
const FULL_CORNERS = [[0, -H / 2], [W / 2, -H / 4], [W / 2, H / 4], [0, H / 2], [-W / 2, H / 4], [-W / 2, -H / 4]]

const RANK_LABEL = { vanguard: "Vanguard", cavalry: "Cavalry", range: "Range", unique: "Unique", mountain: "Mountain" }

// Every unit's hex is shaded in its team's colour from the edge in towards
// the centre (blue yours, red theirs), and the more a piece is worth the
// deeper the shade reaches and the stronger it gets. Worth is the computer's
// own ranking (KILL_PRIORITY, rabble up to king); mountains sit below it.
const TEAM_SHADE = { 1: "#3b82f6", 0: "#dc2626" }
const SHADE_RANKS = ["mountain", ...KILL_PRIORITY]
const TOP_RANK = SHADE_RANKS.length - 1

// Rank 0 is a faint rim; the top rank floods in to near the centre.
function shadeStops(rank) {
  const t = rank / TOP_RANK
  const clear = Math.round(62 - t * 50)
  const edge = (0.3 + t * 0.7).toFixed(2)
  return [[`${clear}%`, 0], ["100%", edge]]
}

export default class extends Controller {
  static targets = ["board", "banner", "status", "dock", "setupControls", "startButton", "info", "graveyard", "opponent", "hint", "threatToggle"]
  static values = { skin: { type: String, default: "vector" }, images: Object, skins: Object, pace: { type: Number, default: 1 } }

  connect() {
    this.timers = new Set()
    this.buildBoard()
    this.newGame()
  }

  disconnect() {
    this.clearTimers()
    this.bannerBox.hide()
  }

  // ---- Game lifecycle ------------------------------------------------------

  newGame() {
    this.clearTimers()
    this.game = new Game()
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
  }

  randomSetup() {
    if (this.game.phase !== "setup") return
    this.game.randomSetup()
    this.selectedUnitId = null
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
    this.banner(`${passed ? (this.game.offense === PLAYER ? "Opponent passes · " : "You pass · ") : ""}Turn ${this.game.turn} · ${whose}`)
    if (this.game.offense === COMPUTER) this.computerTurn()
  }

  // The legacy AI's rhythm: think 1.5 s, show its unit's rings, move a second
  // later, and a second after that for a cavalry unit's second jump.
  computerTurn() {
    const action = chooseAction(this.game)
    if (!action) return
    this.later(1500, () => {
      this.select(action.from)
      this.later(1000, () => {
        const result = this.game.act(action.from, action.to)
        if (result.secondJump) {
          this.select(this.game.activeHex)
          this.later(1000, () => {
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
    const text = this.game.winner === PLAYER ? `You win, at turn ${this.game.turn}.` : `You were defeated, at turn ${this.game.turn}.`
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
    const node = event.target.closest("[data-hex]")
    if (!node || this.holding) return
    const hex = Number(node.dataset.hex)
    if (this.game.phase === "setup") return this.setupClick(hex)
    if (this.game.phase === "play" && this.game.offense === PLAYER) this.playClick(hex)
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
  }

  setupClick(hex) {
    const unit = this.game.pieceAt(hex)
    if (unit?.team === PLAYER) {
      this.selectedUnitId = unit.id
    } else if (this.selectedUnitId && !unit && inPlayerZone(hex)) {
      this.game.place(this.selectedUnitId, hex)
      this.selectedUnitId = null
    }
    this.render()
  }

  playClick(hex) {
    if (this.actions && (this.actions.moves.includes(hex) || this.actions.attacks.includes(hex))) {
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
    if (this.game.selectableHexes().includes(hex)) this.select(hex)
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
    this.showThreats = event.target.checked
    try {
      window.localStorage.setItem(THREATS_KEY, this.showThreats ? "on" : "off")
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
      SHADE_RANKS.forEach((_, rank) => {
        const gradient = el("radialGradient", { id: `shade-${team}-${rank}`, r: "60%" })
        for (const [offset, opacity] of shadeStops(rank)) {
          gradient.append(el("stop", { offset, "stop-color": color, "stop-opacity": opacity }))
        }
        defs.append(gradient)
      })
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
        const [s, l] = entry.split(",").map((part) => parseFloat(part))
        for (const [kind, stops] of Object.entries(RANGE_STOPS)) gradientOf(`${kind}-${table}-${step}`, stops(s, l))
      })
    }
    // The texture over a lit hex: a fine diagonal hatch, light and faint.
    const texture = el("pattern", { id: "ring-texture", patternUnits: "userSpaceOnUse", width: 5, height: 5, patternTransform: "rotate(40)" })
    texture.append(el("line", { x1: 0, y1: 0, x2: 0, y2: 5, stroke: "white", "stroke-opacity": 0.14, "stroke-width": 1.2 }))
    texture.append(el("line", { x1: 2.5, y1: 0, x2: 2.5, y2: 5, stroke: "black", "stroke-opacity": 0.1, "stroke-width": 0.8 }))
    defs.append(texture)
    svg.append(defs)
    this.hexNodes = new Map()
    this.hexCentres = new Map()
    this.hexPolygons = new Map()

    const corners = [[0, -H / 2], [W / 2, -H / 4], [W / 2, H / 4], [0, H / 2], [-W / 2, H / 4], [-W / 2, -H / 4]]
      .map(([x, y]) => `${(x * 0.97).toFixed(2)},${(y * 0.97).toFixed(2)}`).join(" ")

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
      const danger = el("circle", { class: "danger-ring", r: 28.5 })
      const disc = el("circle", { class: "unit-disc", r: 27 })
      const image = el("image", { class: "unit-image", x: -28, y: -30, width: 56, height: 60 })
      group.append(polygon, texture, shade, danger, disc, image)
      svg.append(group)
      this.hexNodes.set(hex.index, { group, polygon, shade, disc, image })
      this.hexCentres.set(hex.index, { x: cx, y: cy, row: hex.y })
      this.hexPolygons.set(hex.index, FULL_CORNERS.map(([dx, dy]) => [cx + dx, cy + dy]))
    }
    // The opponent's reach, drawn as one outline over the board (renderThreats).
    // It lies over the resting board but beneath the selection and the move
    // rings: the mask cuts it away over every hex that carries one of those
    // (maskThreats), so they read clean wherever the outline runs.
    const mask = el("mask", { id: `${this.identifier}-threat-mask`, maskUnits: "userSpaceOnUse", x: 0, y: 0, width, height })
    mask.append(el("rect", { x: 0, y: 0, width, height, fill: "white" }))
    this.threatHoles = el("g", { fill: "black" })
    mask.append(this.threatHoles)
    defs.append(mask)
    this.threatPath = el("path", { class: "threat-outline", mask: `url(#${this.identifier}-threat-mask)` })
    svg.append(this.threatPath)

    // What a screen reader says after a threatened unit's name (renderThreats).
    // Visually hidden text, joined to the name with aria-labelledby, because
    // Safari's VoiceOver reads aria-description only in part.
    const noteId = `${this.identifier}-danger-note`
    this.dangerNote = document.getElementById(noteId) ?? document.createElement("span")
    this.dangerNote.id = noteId
    this.dangerNote.className = "cyvasse-visually-hidden"
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
        const rank = SHADE_RANKS.indexOf(unit.type.codename)
        node.group.dataset.rank = rank
        node.shade.setAttribute("fill", `url(#shade-${unit.team}-${rank})`)
      } else {
        delete node.group.dataset.rank
        node.shade.removeAttribute("fill")
      }
      node.group.setAttribute("aria-label", unit ? `${unit.team === PLAYER ? "Your" : "Enemy"} ${unit.type.name.toLowerCase()}` : `Hex ${index}`)
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
    } else {
      for (const hex of [...game.lastMove, game.utilMove]) {
        if (hex) this.hexNodes.get(hex).group.classList.add("is-last-move")
      }
    }

    this.paintGround()
    this.renderThreats()
    this.renderHint()
    this.renderDock()
    this.renderStatus()
    this.renderGraveyards()
    this.renderInfo(this.selectedUnitId ? game.unit(this.selectedUnitId) : null)
  }

  // Each hex's resting fill, from the classes render() just set. It is the
  // polygon's fill attribute, so the stylesheet's orange (the selection and
  // the last move) and a ring's inline gradient both draw over it.
  paintGround() {
    for (const { group, polygon } of this.hexNodes.values()) {
      const ground = group.classList.contains("is-drop") ? "hex-drop" : group.classList.contains("is-deploy") ? "hex-deploy" : "hex-base"
      polygon.setAttribute("fill", `url(#${ground})`)
    }
  }

  // Where the opponent could strike next turn (cyvasse/threats, from the
  // rules' own legal actions): the outer edge of that region is outlined, the
  // opponent's own units counted in so the outline is one shape rather than
  // a ring round each of them, and every unit of yours they could actually
  // kill wears the danger ring. Play only; the switch turns it off.
  renderThreats() {
    const game = this.game
    // Read once per page, by /play and the match board alike.
    this.showThreats ??= threatsWanted()
    const live = game.phase === "play" && this.showThreats
    if (this.hasThreatToggleTarget) {
      this.threatToggleTarget.checked = this.showThreats
      this.threatToggleTarget.closest("label").hidden = game.phase !== "play"
    }
    const { reach, kills } = live ? threats(game, 1 - PLAYER) : { reach: new Set(), kills: new Set() }
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
    if (!live) return this.threatPath.setAttribute("d", "")

    const region = new Set(reach)
    for (const unit of game.teamUnits(1 - PLAYER, "alive")) region.add(unit.hex)
    const d = outlineEdges(region, this.hexPolygons)
      .map(([[ax, ay], [bx, by]]) => `M${ax.toFixed(1)} ${ay.toFixed(1)}L${bx.toFixed(1)} ${by.toFixed(1)}`).join("")
    this.threatPath.setAttribute("d", d)
    this.maskThreats()
  }

  // Cut the threat outline away over the hexes the selection and its rings
  // light, so the outline paints beneath them (see buildBoard's mask).
  maskThreats() {
    if (!this.threatHoles) return
    const holes = []
    for (const [index, { group }] of this.hexNodes) {
      if (!HIGHLIGHTS.some((name) => group.classList.contains(name))) continue
      holes.push(el("polygon", { points: this.hexPolygons.get(index).map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" ") }))
    }
    this.threatHoles.replaceChildren(...holes)
  }

  // The "start over" hint shows while there is something to start over from.
  renderHint() {
    if (!this.hasHintTarget) return
    const game = this.game
    const picked = game.phase === "setup" ? !!this.selectedUnitId
      : game.phase === "play" && (this.selectedHex != null || (!!this.pendingJump && game.jump === 2))
    this.hintTarget.hidden = !picked || this.holding
  }

  renderDock() {
    const unplaced = this.game.teamUnits(PLAYER, "unplaced")
    this.dockTarget.replaceChildren(...unplaced.map((unit) => {
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
  }

  renderStatus() {
    const game = this.game
    let text
    if (game.phase === "setup") {
      const left = game.teamUnits(PLAYER, "unplaced").length
      text = left > 0 ? `Place your army: ${left} unit${left === 1 ? "" : "s"} left.` : "Your army is in place. Press Ready."
    } else if (game.phase === "over") {
      text = game.winner === PLAYER ? "You win." : game.winner === COMPUTER ? "You were defeated." : "A draw."
    } else if (game.offense === PLAYER) {
      text = game.jump === 2 ? `Turn ${game.turn}: your cavalry jumps again.` : `Turn ${game.turn}: your move.`
    } else {
      text = `Turn ${game.turn}: the opponent is thinking.`
    }
    this.statusTarget.textContent = this.notice && game.phase === "play" ? `${this.notice} ${text}` : text
  }

  renderGraveyards() {
    for (const target of this.graveyardTargets) {
      const team = Number(target.dataset.team)
      target.replaceChildren(...this.game.graveyard(team).map((u) => img(this.imagesValue[u.type.codename], u.type.name)))
    }
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
      const movement = type.codename === "dragon" ? "Straight line" : type.rank === "cavalry" ? `${type.moveRange} + 2` : type.moveRange
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
    node.polygon.style.fill = "orange"
    for (const i of this.actions.moves) this.hexNodes.get(i).group.classList.add("is-move")
    for (const i of this.actions.attacks) this.hexNodes.get(i).group.classList.add("is-attack")
    this.maskThreats()
    this.ripple(unit)
    this.renderHint()
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
    const reach = shooter ? type.attackRange : type.rank === "cavalry" ? type.moveRange * 2 : type.moveRange
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
      this.maskThreats()
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
