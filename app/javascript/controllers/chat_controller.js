import { Controller } from "@hotwired/stimulus"

// The match chat (app/views/matches/_chat.html.erb). The message list is a
// Turbo frame; this reloads it every few seconds while the tab is visible.
//
// - Scrolling: the list follows the newest message only while the reader is
//   at (or near) the bottom, or has just sent one. A reader scrolled up to
//   read older messages stays where they are through every reload.
// - Errors: a refused message comes back inside the frame, which the next
//   reload would wipe; it is moved to the error line outside the frame and
//   stays until the next message is sent.
// - Enter sends on a keyboard (Shift+Enter starts a new line). On a touch
//   screen Enter is a new line, as phones expect, and Send sends.
// - New messages from the other player are announced to screen readers.
export default class extends Controller {
  static targets = ["frame", "input", "error", "announcer"]
  static values = { refreshMs: { type: Number, default: 8000 } }

  // How close to the bottom (px) still counts as "at the bottom".
  static NEAR_BOTTOM = 48

  connect() {
    this.follow = true
    this.lastId = null
    this.timer = setInterval(() => this.refresh(), this.refreshMsValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  refresh() {
    if (document.visibilityState !== "visible" || !this.frameTarget.src) return
    if (this.frameTarget.hasAttribute("busy")) return
    this.remember()
    this.frameTarget.reload()
  }

  // Before a reload, note whether the reader is following the bottom and
  // where they are, so loaded() can put them back.
  remember() {
    const log = this.log
    if (!log) return
    this.follow = log.scrollHeight - log.scrollTop - log.clientHeight <= this.constructor.NEAR_BOTTOM
    this.savedTop = log.scrollTop
  }

  // turbo:frame-load: after the first load, every reload, and a send.
  loaded() {
    this.liftError()
    const log = this.log
    if (log) log.scrollTop = this.follow ? log.scrollHeight : this.savedTop
    this.announceNew()
  }

  // turbo:submit-start: sending jumps to the bottom to show the new message.
  sending() {
    this.follow = true
  }

  sent(event) {
    if (!event.detail.success) return
    this.inputTarget.value = ""
    this.showError(null)
    this.inputTarget.focus()
  }

  submitOnEnter(event) {
    if (event.shiftKey || event.isComposing || this.touchScreen) return
    event.preventDefault()
    if (this.inputTarget.value.trim() === "") return
    this.inputTarget.form.requestSubmit()
  }

  // ---- private ---------------------------------------------------------------

  get log() {
    return this.frameTarget.querySelector("[data-chat-log]")
  }

  get touchScreen() {
    return window.matchMedia?.("(pointer: coarse)").matches ?? false
  }

  liftError() {
    const error = this.frameTarget.querySelector("[data-chat-error]")
    if (!error) return
    this.showError(error.textContent.trim())
    error.remove()
  }

  showError(text) {
    this.errorTarget.textContent = text ?? ""
    this.errorTarget.hidden = !text
  }

  // Say "New message from <name>" for messages from the other player that
  // arrived since the last load; nothing on the first load.
  announceNew() {
    const messages = [...this.frameTarget.querySelectorAll("[data-message-id]")]
    const newest = Math.max(0, ...messages.map((m) => Number(m.dataset.messageId)))
    if (this.lastId !== null) {
      const fresh = messages.filter((m) => Number(m.dataset.messageId) > this.lastId && !m.classList.contains("is-mine"))
      if (fresh.length > 0) {
        const last = fresh[fresh.length - 1]
        const from = last.querySelector("[data-sender]")?.textContent.trim() ?? "your opponent"
        const text = last.querySelector(".chat-text")?.textContent.trim() ?? ""
        this.announcerTarget.textContent = fresh.length === 1 ? `New message from ${from}: ${text}` : `${fresh.length} new messages from ${from}.`
      }
    }
    this.lastId = newest
  }
}
