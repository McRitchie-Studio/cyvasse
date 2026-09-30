import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// One live conversation (app/views/chat/_thread.html.erb): the Chat hub's
// thread and the match chat (task cyvasse-live-chat). New messages arrive
// over the pair's websocket stream as Turbo Stream appends; no polling.
//
// - Mine: a broadcast message is drawn once for both people, so each message
//   from the reader is marked here (is-mine, "You") from data-sender-id.
// - Scrolling: the list follows the newest message only while the reader is
//   at (or near) the bottom, or has just sent one. "Load earlier" keeps the
//   reader where they were while older messages land above.
// - Read: messages from the other person are marked read (POST readUrl)
//   while the list is on screen and the tab is visible, which clears the
//   navbar badge live.
// - Announced: a new message from the other person is read out by screen
//   readers through the polite live region.
// - Reconnect: Turbo's cable source reconnects by itself, but anything sent
//   while the socket was down is not replayed, so on reconnect (and on
//   coming back to the tab) the thread asks for the messages since the last
//   one it has (sinceUrl) and appends them.
// - Errors: a refused message's reason is shown in the error line (the
//   server replaces it) and the draft is kept.
// - Enter sends on a keyboard (Shift+Enter starts a new line). On a touch
//   screen Enter is a new line, as phones expect, and Send sends.
export default class extends Controller {
  static targets = ["log", "message", "input", "error", "announcer", "source", "form", "earlier"]
  static values = {
    viewerId: Number,
    readUrl: String,
    sinceUrl: String,
    unread: Boolean,
    matchId: Number
  }

  // How close to the bottom (px) still counts as "at the bottom".
  static NEAR_BOTTOM = 48

  initialize() {
    this.lastId = 0
    this.ready = false
  }

  connect() {
    this.follow = true
    this.onScreen = false
    this.pendingRead = this.unreadValue
    this.scrollToEnd()
    this.onScroll = () => this.logScrolled()
    this.logTarget.addEventListener("scroll", this.onScroll, { passive: true })
    this.watchVisibility()
    this.watchSocket()
    this.onVisible = () => {
      if (document.visibilityState !== "visible") return
      this.catchUp()
      this.markReadIfSeen()
    }
    document.addEventListener("visibilitychange", this.onVisible)
    this.ready = true
  }

  disconnect() {
    this.ready = false
    this.visibility?.disconnect()
    this.socket?.disconnect()
    this.logTarget.removeEventListener("scroll", this.onScroll)
    document.removeEventListener("visibilitychange", this.onVisible)
  }

  // Every message element, whether rendered with the page, appended live, or
  // loaded from "Load earlier". Stimulus calls this for the first ones before
  // connect(), so nothing is announced then.
  messageTargetConnected(element) {
    this.markMine(element)
    this.hideOwnMatchLabel(element)
    // Older messages from "Load earlier" are history, never news.
    if (element.closest("turbo-frame")) return
    const id = Number(element.dataset.messageId)
    const isNew = id > this.lastId
    if (isNew) this.lastId = id
    if (!this.ready || !isNew) return

    if (element.classList.contains("is-mine")) {
      this.follow = true
    } else {
      this.announce(element)
      this.pendingRead = true
      this.markReadIfSeen()
    }
    if (this.follow) this.scrollToEnd()
  }

  // As the reader scrolls, note whether they are following the bottom.
  logScrolled() {
    const log = this.logTarget
    this.follow = log.scrollHeight - log.scrollTop - log.clientHeight <= this.constructor.NEAR_BOTTOM
  }

  // "Load earlier messages" clicked: keep the reader's distance from the
  // bottom while older messages are inserted above.
  loadingEarlier(event) {
    const frame = event.target.closest("turbo-frame")
    if (!frame) return
    const log = this.logTarget
    const fromBottom = log.scrollHeight - log.scrollTop
    frame.addEventListener("turbo:frame-load", () => {
      log.scrollTop = log.scrollHeight - fromBottom
      frame.querySelector("a, button")?.focus?.()
    }, { once: true })
  }

  // turbo:submit-start: sending jumps to the bottom to show the new message.
  sending() {
    this.follow = true
  }

  sent(event) {
    if (!event.detail.success) return
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }

  submitOnEnter(event) {
    if (event.shiftKey || event.isComposing || this.touchScreen) return
    event.preventDefault()
    if (this.inputTarget.value.trim() === "") return
    this.inputTarget.form.requestSubmit()
  }

  // ---- private ---------------------------------------------------------------

  get touchScreen() {
    return window.matchMedia?.("(pointer: coarse)").matches ?? false
  }

  scrollToEnd() {
    if (!this.hasLogTarget) return
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }

  markMine(element) {
    if (Number(element.dataset.senderId) !== this.viewerIdValue) return
    element.classList.add("is-mine")
    const name = element.querySelector("[data-sender]")
    if (name) name.textContent = "You"
  }

  // On the match page, "in match #12" on this match's own messages says
  // nothing; messages from their other matches keep it.
  hideOwnMatchLabel(element) {
    if (!this.matchIdValue) return
    const label = element.querySelector(`[data-match-label="${this.matchIdValue}"]`)
    if (label) label.hidden = true
  }

  announce(element) {
    const from = element.dataset.senderName || "your opponent"
    const text = element.querySelector(".chat-text")?.textContent.trim() ?? ""
    this.announcerTarget.textContent = `New message from ${from}: ${text}`
  }

  // The log counts as seen while any of it is in the viewport.
  watchVisibility() {
    if (!("IntersectionObserver" in window)) {
      this.onScreen = true
      this.markReadIfSeen()
      return
    }
    this.visibility = new IntersectionObserver((entries) => {
      this.onScreen = entries.some((entry) => entry.isIntersecting)
      this.markReadIfSeen()
    })
    this.visibility.observe(this.logTarget)
  }

  markReadIfSeen() {
    if (!this.pendingRead || !this.onScreen || document.visibilityState !== "visible") return
    if (!this.readUrlValue || this.reading) return
    this.pendingRead = false
    this.reading = true
    fetch(this.readUrlValue, { method: "POST", headers: { "X-CSRF-Token": this.csrfToken }, credentials: "same-origin" })
      .then((response) => { if (!response.ok) this.pendingRead = true })
      .catch(() => { this.pendingRead = true })
      .finally(() => { this.reading = false })
  }

  // The cable source carries a `connected` attribute while subscribed.
  // Losing it and getting it back means messages may have been missed.
  watchSocket() {
    if (!this.hasSourceTarget) return
    this.wasConnected = this.sourceTarget.hasAttribute("connected")
    this.socket = new MutationObserver(() => {
      const connected = this.sourceTarget.hasAttribute("connected")
      if (connected && this.wasConnected === false) this.catchUp()
      this.wasConnected = connected
    })
    this.socket.observe(this.sourceTarget, { attributes: true, attributeFilter: ["connected"] })
  }

  async catchUp() {
    if (!this.sinceUrlValue || this.catchingUp) return
    this.catchingUp = true
    try {
      const url = new URL(this.sinceUrlValue, window.location.href)
      url.searchParams.set("after", String(this.lastId))
      const response = await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin" })
      if (response.ok) {
        const html = await response.text()
        if (html.trim() !== "") Turbo.renderStreamMessage(html)
      }
    } catch {
      // Offline again: the next reconnect tries once more.
    } finally {
      this.catchingUp = false
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
  }
}
