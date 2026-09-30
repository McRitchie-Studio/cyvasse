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
