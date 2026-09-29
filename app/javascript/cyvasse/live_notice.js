// The live match's strike and seat notice (LiveMatch): which line, if any,
// sits in the match sidebar. `live` is Match#state_for's live block, `phase`
// the match phase, `them` the opponent's name. Answers { text, held }: held
// is the computer's hold on this player's seat, which only "Take back my
// seat" ends, so it cannot be dismissed.
//
// A finished match has no clocks left to miss and no seat to take back, so
// it has no notice: "Miss one more clock…" beside "Your king fell." reads as
// a threat about a game already over.
export function liveNotice(live, phase, them) {
  const none = { text: "", held: false }
  if (!live || phase === "over") return none
  if (live.taken_over?.you) {
    return { text: "You missed two clocks, so a computer player has taken your seat. Take it back to play on.", held: true }
  }
  let text = ""
  if (live.taken_over?.opponent) text = `${them} missed two clocks, so a computer player has taken their seat.`
  else if (live.took_back?.you) text = "You took back your seat. Miss one more clock and a computer player takes it again."
  else if (live.took_back?.opponent) text = `${them} took back their seat from the computer player.`
  else if (live.auto_set_up?.you && live.strikes?.you === 1) text = "Time ran out, so your army was placed for you. Miss one more clock and a computer player takes your seat."
  else if (live.strikes?.you === 1) text = "You missed a clock and a move was made for you. Miss one more and a computer player takes your seat."
  else if (live.strikes?.opponent === 1) text = `${them} missed a clock.`
  return { text, held: false }
}
