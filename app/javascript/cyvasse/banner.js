// The rotator banner over the board (legacy goodCode/rotator.js): a line that
// slides in, holds, and slides out. Shared by /play and online matches.
//
// One banner shows at a time. A new one cancels the old one's timers, so a
// turn banner still counting down can never slide away the "You win" that
// replaced it; and a banner that has slid out is hidden again, so it no
// longer sits invisible over the board.
//
// No DOM beyond the node it is given, and the clock is injectable, so the
// node unit tests (test/javascript/banner_test.js) drive it with fake timers.

export const BANNER_MS = 1800
export const LEAVE_MS = 600

export class Banner {
  #node
  #pace
  #schedule
  #cancel
  #timer = null

  constructor(node, { pace = () => 1, schedule = (fn, ms) => setTimeout(fn, ms), cancel = (id) => clearTimeout(id) } = {}) {
    this.#node = node
    this.#pace = pace
    this.#schedule = schedule
    this.#cancel = cancel
  }

  // Show `text`. Unless `stay`, it slides out after BANNER_MS and `then` runs
  // as it leaves; with `stay` it holds and `then` runs at once.
  show(text, then = null, { stay = false } = {}) {
    this.#stop()
    const node = this.#node
    node.textContent = text
    node.hidden = false
    node.classList.remove("is-leaving")
    node.classList.add("is-showing")
    if (stay) {
      if (then) then()
      return
    }
    this.#timer = this.#schedule(() => {
      node.classList.add("is-leaving")
      node.classList.remove("is-showing")
      this.#timer = this.#schedule(() => this.hide(), LEAVE_MS * this.#pace())
      if (then) then()
    }, BANNER_MS * this.#pace())
  }

  hide() {
    this.#stop()
    this.#node.hidden = true
    this.#node.classList.remove("is-showing", "is-leaving")
  }

  #stop() {
    if (this.#timer !== null) this.#cancel(this.#timer)
    this.#timer = null
  }
}

// The line for a turn that passed because its side had no legal move (the
// stalemate rule, Game#beginTurn). `passer` is PLAYER (1) or the computer (0).
export function passNotice(passer, opponentName) {
  return passer === 1
    ? "You have no legal move, so your turn passes."
    : `${opponentName} has no legal move and passes.`
}
