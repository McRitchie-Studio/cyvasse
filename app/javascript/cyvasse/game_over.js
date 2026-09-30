// The game-over modal's points line (modals/_game_over), from the live
// state's board_points and board_rank (LiveMatch#live_state_for). The points
// are the server's (Match#leaderboard_points, the leaderboard's own rule);
// this only words them. Empty when the game put nothing on the board: 0 (a
// seat the computer held at the end) or null (a game that does not count).
export function pointsLine({ points, win, rank } = {}) {
  if (!(points > 0)) return ""
  const amount = `+${points} ${points === 1 ? "point" : "points"} on the leaderboard`
  const line = win ? `${amount}.` : `${amount} for finishing.`
  return rank ? `${line} You’re now #${rank}.` : line
}

// The navbar's Leaderboard badge (NavbarLinks#rank_badge, drawn by the
// engine's studio_navbar_link_tag) is rendered with the page, so after a game
// it showed the old rank until the next page load (production UX audit #14).
// When the game-over state brings the player's new rank, it is written into
// every Leaderboard link in the navbar (the desktop bar and the phone row),
// adding the badge for a player who was not on the board before. The class is
// the engine's StudioNavbarHelper::NAVBAR_BADGE_CLASS
// (test/views/navbar_links_test.rb holds the two equal).
export const NAV_LEADERBOARD = "header[data-pin=nav] a[href='/leaderboard']"
export const NAV_BADGE_CLASS = "rounded-full border border-subtle px-1.5 py-0.5 text-[10px] leading-none " +
  "font-semibold text-muted tabular-nums"

export function rankBadge(rank) {
  return Number.isInteger(rank) && rank > 0 ? `#${rank}` : null
}

export function refreshNavRank(doc, rank) {
  const text = rankBadge(rank)
  if (!text) return 0
  const links = [...doc.querySelectorAll(NAV_LEADERBOARD)]
  links.forEach((link) => {
    let badge = [...link.children].find((child) => child.tagName === "SPAN")
    if (!badge) {
      badge = doc.createElement("span")
      badge.className = NAV_BADGE_CLASS
      link.append(badge)
    }
    badge.textContent = text
    badge.dataset.navRank = "live"
  })
  return links.length
}
