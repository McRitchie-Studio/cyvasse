import { Controller } from "@hotwired/stimulus"
import { Game, PLAYER, COMPUTER } from "cyvasse/game"
import { chooseAction } from "cyvasse/ai"
import { HEXES, hexAt, inPlayerZone } from "cyvasse/board"
import { UNIT_TYPES } from "cyvasse/units"

// The Cyvasse board at /play: one game against the computer, in the browser.
//
// The rules live in app/javascript/cyvasse (tested under test/javascript);
// this controller only draws a Game and turns clicks into Game calls. The
// look follows the legacy match screen: black hexes with white edges, orange
// for the last move, and the ring ripple (animation.js) washing out from a
// selected unit in the legacy colours, one ring every 120 ms.
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
const BANNER_MS = 1800

// Legacy Animation.hslRange: saturation and lightness per ring, brightening
// outward. The dragon's longer reach uses the ten-step table.
const HSL_SHORT = ["40%,30%", "42%,39%", "44%,47%", "46%,50%", "48%,55%", "50%,60%"]
const HSL_LONG = ["40%,30%", "41%,34%", "42%,38%", "43%,42%", "44%,45%", "45%,48%", "46%,51%", "47%,54%", "48%,57%", "50%,60%"]
// Move ring code -> hue (animation.js updateRing).
const MOVE_HUE = { 1: 240, 2: 290, 3: 10, 4: 10, 5: 280 }
const PREVIEW_STROKE = { 6: "blue", 7: "red", 8: "purple" }
const RANGE_STROKE = { 1: "red", 2: "red", 3: "blue", 4: "blue" }

const RANK_LABEL = { vanguard: "Vanguard", cavalry: "Cavalry", range: "Range", unique: "Unique", mountain: "Mountain" }

export default class extends Controller {
  static targets = ["board", "banner", "status", "dock", "setupControls", "startButton", "info", "graveyard", "opponent"]
  static values = { skin: { type: String, default: "vector" }, images: Object, skins: Object, pace: { type: Number, default: 1 } }

  connect() {
    this.timers = new Set()
    this.buildBoard()
    this.newGame()
  }

  disconnect() {
    this.clearTimers()
  }

  // ---- Game lifecycle ------------------------------------------------------

  newGame() {
    this.clearTimers()
    this.game = new Game()
    this.holding = false
    this.selectedUnitId = null
    this.selectedHex = null
    this.actions = null
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

  start() {
    if (!this.game.readyToStart) return
    this.game.start()
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
  runTurn() {
    this.holding = false
    this.clearSelection()
    this.render()
    if (this.game.phase === "over") return this.announceWinner()

    const whose = this.game.offense === PLAYER ? "Your move" : "Opponent’s move"
    this.banner(`Turn ${this.game.turn} · ${whose}`)
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
            this.game.act(next.from, next.to)
            this.runTurn()
          })
        } else {
          this.runTurn()
        }
      })
    })
  }

  announceWinner() {
    if (this.game.winner === null) return this.banner("Neither side can move. A draw.", null, { stay: true })
    const text = this.game.winner === PLAYER ? `You win, at turn ${this.game.turn}.` : `You were defeated, at turn ${this.game.turn}.`
    this.banner(text, null, { stay: true })
  }

  // ---- Clicks --------------------------------------------------------------

  clickHex(event) {
    const node = event.target.closest("[data-hex]")
    if (!node || this.holding) return
    const hex = Number(node.dataset.hex)
    if (this.game.phase === "setup") return this.setupClick(hex)
    if (this.game.phase === "play" && this.game.offense === PLAYER) this.playClick(hex)
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
      const result = this.game.act(this.selectedHex, hex)
      if (result.secondJump) {
        this.render()
        this.select(this.game.activeHex)
      } else {
        this.runTurn()
      }
      return
    }
    if (this.game.selectableHexes().includes(hex)) this.select(hex)
  }

  // ---- Drawing -------------------------------------------------------------

  buildBoard() {
    const width = 11 * W + PAD * 2
    const height = 10 * H * 0.75 + H + PAD * 2
    const svg = this.boardTarget
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`)
    svg.replaceChildren()
    this.hexNodes = new Map()

    const corners = [[0, -H / 2], [W / 2, -H / 4], [W / 2, H / 4], [0, H / 2], [-W / 2, H / 4], [-W / 2, -H / 4]]
      .map(([x, y]) => `${(x * 0.97).toFixed(2)},${(y * 0.97).toFixed(2)}`).join(" ")

    for (const hex of HEXES) {
      const cx = PAD + (11 - hex.size) * W / 2 + (hex.x - 0.5) * W
      const cy = PAD + H / 2 + (hex.y - 1) * H * 0.75
      const group = el("g", { class: "hex", "data-hex": hex.index, transform: `translate(${cx.toFixed(2)} ${cy.toFixed(2)})` })
      const polygon = el("polygon", { class: "hex-poly", points: corners })
      const disc = el("circle", { class: "unit-disc", r: 24 })
      const image = el("image", { class: "unit-image", x: -22, y: -24, width: 44, height: 48 })
      group.append(polygon, disc, image)
      svg.append(group)
      this.hexNodes.set(hex.index, { group, polygon, disc, image })
    }
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
    if (!this.skinsValue[skin] || skin === this.skinValue) return

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
      node.group.classList.remove("is-move", "is-attack", "is-selected", "is-deploy", "is-last-move")
      node.group.dataset.unitId = unit?.id ?? ""
      node.group.dataset.team = unit ? unit.team : ""
      node.group.setAttribute("aria-label", unit ? `${unit.team === PLAYER ? "Your" : "Enemy"} ${unit.type.name.toLowerCase()}` : `Hex ${index}`)
      if (unit) {
        node.image.setAttribute("href", this.imagesValue[unit.type.codename])
      } else {
        node.image.removeAttribute("href")
      }
      node.polygon.style.fill = ""
      node.polygon.style.stroke = ""
    }

    if (game.phase === "setup") {
      for (const [index, node] of this.hexNodes) {
        if (inPlayerZone(index)) node.group.classList.add("is-deploy")
      }
      const selected = this.selectedUnitId && game.unit(this.selectedUnitId)
      if (selected?.hex) this.hexNodes.get(selected.hex).group.classList.add("is-selected")
    } else {
      for (const hex of [...game.lastMove, game.utilMove]) {
        if (hex) this.hexNodes.get(hex).group.classList.add("is-last-move")
      }
    }

    this.renderDock()
    this.renderStatus()
    this.renderGraveyards()
    this.renderInfo(this.selectedUnitId ? game.unit(this.selectedUnitId) : null)
  }

  renderDock() {
    const unplaced = this.game.teamUnits(PLAYER, "unplaced")
    this.dockTarget.replaceChildren(...unplaced.map((unit) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "dock-unit"
      button.dataset.unitId = unit.id
      button.dataset.action = "cyvasse-game#pickFromDock"
      button.setAttribute("aria-pressed", unit.id === this.selectedUnitId)
      button.setAttribute("aria-label", unit.type.name)
      button.append(img(this.imagesValue[unit.type.codename], unit.type.name))
      return button
    }))
    this.startButtonTarget.hidden = !this.game.readyToStart
  }

  renderStatus() {
    const game = this.game
    let text
    if (game.phase === "setup") {
      const left = game.teamUnits(PLAYER, "unplaced").length
      text = left > 0 ? `Place your army: ${left} unit${left === 1 ? "" : "s"} left.` : "Your army is ready. Start the game."
    } else if (game.phase === "over") {
      text = game.winner === PLAYER ? "You win." : game.winner === COMPUTER ? "You were defeated." : "A draw."
    } else if (game.offense === PLAYER) {
      text = game.jump === 2 ? `Turn ${game.turn}: your cavalry jumps again.` : `Turn ${game.turn}: your move.`
    } else {
      text = `Turn ${game.turn}: the opponent is thinking.`
    }
    this.statusTarget.textContent = text
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
    this.ripple(unit)
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
    const hsl = type.moveRange > 5 ? HSL_LONG : HSL_SHORT
    const { rings, rangeRings } = this.actions
    const reach = type.rank === "range" ? type.attackRange : type.rank === "cavalry" ? type.moveRange * 2 : type.moveRange
    let distance = 1

    const paint = () => {
      const step = distance - 1
      for (const [index, ring] of rings) {
        if (ring % 10 !== step || ring < 10) continue
        const code = Math.floor(ring / 10)
        const polygon = this.hexNodes.get(index).polygon
        if (MOVE_HUE[code] !== undefined) polygon.style.fill = `hsl(${MOVE_HUE[code]}, ${hsl[step]})`
        if (PREVIEW_STROKE[code]) polygon.style.stroke = PREVIEW_STROKE[code]
      }
      if (type.rank === "range") {
        for (const [index, ring] of rangeRings) {
          if (ring % 10 !== step || ring < 10) continue
          const code = Math.floor(ring / 10)
          const polygon = this.hexNodes.get(index).polygon
          if (code === 2) polygon.style.fill = `hsl(10, ${hsl[step]})`
          if (RANGE_STROKE[code]) polygon.style.stroke = RANGE_STROKE[code]
        }
      }
      distance += 1
    }

    if (this.paceValue === 0) {
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

  banner(text, then = null, { stay = false } = {}) {
    const node = this.bannerTarget
    node.textContent = text
    node.hidden = false
    node.classList.remove("is-leaving")
    node.classList.add("is-showing")
    if (stay) {
      if (then) then()
      return
    }
    this.later(BANNER_MS, () => {
      node.classList.add("is-leaving")
      node.classList.remove("is-showing")
      if (then) then()
    })
  }

  hideBanner() {
    this.bannerTarget.hidden = true
    this.bannerTarget.classList.remove("is-showing", "is-leaving")
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
