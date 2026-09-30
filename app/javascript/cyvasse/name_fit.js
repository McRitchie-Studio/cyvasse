// A player's name that fits its box without breaking mid-word (task
// cyvasse-splash-name-fit). A name wraps only at a space; a word too wide for
// the box shrinks the name, a half pixel at a time, down to a floor; only a
// word still too wide at the floor is cut with an ellipsis, and the whole name
// stays in the element's title. The CSS half is .player-name
// (tailwind/application.css). Driven by controllers/name_fit_controller.

export const FIT_STEP_PX = 0.5

// The largest size from `base` down to `floor` at which nothing overflows,
// or the floor and `truncated` when even the floor overflows.
// `overflowsAt(px)` lays the name out at px and says whether it overflows.
export function fitSize(base, floor, overflowsAt, step = FIT_STEP_PX) {
  const low = Math.min(base, floor)
  for (let size = base; size >= low; size = Math.round((size - step) * 100) / 100) {
    if (!overflowsAt(size)) return { size, truncated: false }
  }
  return { size: low, truncated: true }
}

// Fits `el` (a .player-name) to its box. A hidden element has no box: it is
// left as is and fitted when it shows.
export function fitName(el, { floor }) {
  el.style.fontSize = ""
  el.classList.remove("is-truncated")
  el.title = el.textContent.trim()
  if (!el.clientWidth) return null
  const base = parseFloat(getComputedStyle(el).fontSize)
  const overflowsAt = (px) => {
    el.style.fontSize = `${px}px`
    return el.scrollWidth > el.clientWidth
  }
  const fit = fitSize(base, floor, overflowsAt)
  el.style.fontSize = fit.size === base ? "" : `${fit.size}px`
  el.classList.toggle("is-truncated", fit.truncated)
  return fit
}
