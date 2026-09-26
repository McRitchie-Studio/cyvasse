import { Controller } from "@hotwired/stimulus"

// The match chat (app/views/matches/_chat.html.erb). The message list is a
// Turbo frame; this reloads it every few seconds while the tab is visible,
// keeps it scrolled to the newest message, clears the box once a message is
// sent, and sends on Enter (Shift+Enter starts a new line).
export default class extends Controller {
  static targets = ["frame", "input"]
  static values = { refreshMs: { type: Number, default: 8000 } }

  connect() {
    this.timer = setInterval(() => this.refresh(), this.refreshMsValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  refresh() {
    if (document.visibilityState !== "visible" || !this.frameTarget.src) return
    if (this.frameTarget.hasAttribute("busy")) return
    this.frameTarget.reload()
  }

  scrollDown() {
    const log = this.frameTarget.querySelector("[data-chat-log]")
    if (log) log.scrollTop = log.scrollHeight
  }

  sent(event) {
    if (!event.detail.success) return
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  submitOnEnter(event) {
    if (event.shiftKey || event.isComposing) return
    event.preventDefault()
    if (this.inputTarget.value.trim() === "") return
    this.inputTarget.form.requestSubmit()
  }
}
