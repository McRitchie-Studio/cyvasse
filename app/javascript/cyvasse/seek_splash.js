// The Play Now splash's timing (live_seek_controller.js), with no DOM and no
// clock of its own, so test/javascript/seek_splash_test.js drives it.
//
// The splash starts the instant the ring reads 0 (or a match is found, or the
// player chooses the computer); the server names the match when it answers,
// and the game opens once both the splash time has run and the match is known.

export const COUNT_TICK_MS = 100
export const SEARCH_POLL_MS = 1000
export const SPLASH_POLL_MS = 250

// Whole seconds left on the search, as the ring shows them.
export function secondsLeft(endsAt, now) {
  return Math.max(0, Math.ceil((endsAt - now) / 1000))
}

export class SplashGate {
  constructor(splashMs) {
    this.splashMs = splashMs
    this.startedAt = null
    this.url = null
  }

  get started() {
    return this.startedAt !== null
  }

  // True only the first time.
  start(now) {
    if (this.started) return false
    this.startedAt = now
    return true
  }

  arrive(url) {
    this.url ||= url
  }

  // Milliseconds until the game may open, or null while it cannot yet.
  wait(now) {
    if (!this.started || !this.url) return null
    return Math.max(0, this.startedAt + this.splashMs - now)
  }
}
