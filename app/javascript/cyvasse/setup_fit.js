// How far a setup scroll moves the page (task cyvasse-dock-landscape-tablet),
// for the board controllers' showBoardForSetup. game.css names each screen's
// setup layout in --setup-fit:
//
// - "bottom": the army card is a sheet at the screen's foot; the board must
//   sit between the pinned navbar and the sheet's top;
// - "side": the card is a sheet at the screen's right; the board must sit
//   between the navbar and the screen's foot;
// - "page": the card stays in the page beside the board (a tablet on its
//   side); the board and the card together must sit between the navbar and
//   the screen's foot;
// - "" (a desktop): nothing to keep, no scroll.
//
// Boxes are viewport rects ({ top, bottom }); pinned is the pinned navbar's
// bottom. Returns the pixels to scroll by, 0 for none.
//
// Already on the screen: leave it, so a placement never moves the page.
// Otherwise centre it in the room, so a line of copy above it that wraps
// anew (the status: "Your army is in place") has slack to take up. Too tall
// for the room: the foot first. The navbar collapses as the page scrolls,
// which lifts the page further, so the room is only known afterwards; the
// board is capped to fit the collapsed room (game.css), and the controller
// checks once more when the collapse has settled.
export const SETUP_FIT_MARGIN = 4

export function setupScrollBy({ fit, board, army, pinned = 0, viewportHeight }) {
  if (!["bottom", "side", "page"].includes(fit)) return 0
  let boxTop = board.top
  let boxBottom = board.bottom
  if (fit === "page") {
    boxTop = Math.min(boxTop, army.top)
    boxBottom = Math.max(boxBottom, army.bottom)
  }
  const top = pinned + SETUP_FIT_MARGIN
  const bottom = (fit === "bottom" ? army.top : viewportHeight) - SETUP_FIT_MARGIN
  if (boxTop >= top - 0.5 && boxBottom <= bottom + 0.5) return 0
  const room = bottom - top
  const height = boxBottom - boxTop
  const by = height <= room ? boxTop - (top + (room - height) / 2) : boxBottom - bottom
  return Math.abs(by) < 1 ? 0 : by
}
