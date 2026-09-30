// Where the board key's panel opens (games/_threat_toggle, board_key
// controller). It drops below its "?" when it fits there. When it does not,
// it opens on the side with more room, above when that is the board, and is
// capped to that room so it scrolls inside itself rather than running off
// the screen (production UX audit #3: on a 390x844 phone the key sat below the
// board and its last five entries ran 118px past the bottom of the screen).
// The room above stops at the sticky navbar's bottom edge, which covers it.
// All numbers are CSS pixels in viewport coordinates.
export const GAP = 6
export const MARGIN = 8

export function placeKey({ toggleTop, toggleBottom, viewportHeight, navBottom = 0, panelHeight }) {
  const below = viewportHeight - toggleBottom - GAP - MARGIN
  const above = toggleTop - Math.max(navBottom, 0) - GAP - MARGIN
  if (panelHeight <= below) return { placement: "below", maxHeight: null }
  if (above > below) return { placement: "above", maxHeight: panelHeight <= above ? null : Math.max(Math.floor(above), 0) }
  return { placement: "below", maxHeight: Math.max(Math.floor(below), 0) }
}
