// Cyvasse Night's clock (night_countdown_controller.js; the night is
// CyvasseNight on the server), with no DOM and no clock of its own, so
// test/javascript/night_clock_test.js drives it.
//
// The window is [start, end): at the start the night is on, at the end it is over.

export const TICK_MS = 1000

export function phaseAt(now, start, end) {
  if (now < start) return "before"
  if (now < end) return "during"
  return "after"
}

// Days, hours, minutes and seconds left until `target`, whole and never
// negative. The seconds round up, so the count reads 0 only at the moment.
export function countdownParts(target, now) {
  let left = Math.max(0, Math.ceil((target - now) / 1000))
  const days = Math.floor(left / 86_400)
  left -= days * 86_400
  const hours = Math.floor(left / 3600)
  left -= hours * 3600
  const minutes = Math.floor(left / 60)
  return { days, hours, minutes, seconds: left - minutes * 60 }
}

export const pad = (n) => String(n).padStart(2, "0")

// "Tuesday, October 6, 9:00 PM EDT" in the visitor's own zone and language.
export function localTimeLabel(start, { locale, timeZone } = {}) {
  return new Intl.DateTimeFormat(locale, {
    weekday: "long", month: "long", day: "numeric", hour: "numeric", minute: "2-digit",
    timeZoneName: "short", ...(timeZone ? { timeZone } : {})
  }).format(new Date(start))
}
