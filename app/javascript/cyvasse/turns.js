// The turn a player reads. The engine (Game#turn, Match#turn) counts
// half-moves: each side's move is one. A player counts full moves, both
// sides' moves together being one turn, as chess does, so "Turn 9" is each
// side's ninth move and never "Turn 17" on a player's ninth. A pass (the
// stalemate rule) takes a half-move like any other. Mirrored in Ruby by
// Match#full_move; held together by test/javascript/turns_test.js and
// test/models/match_full_move_test.rb.
export function fullMove(turn) {
  const halfMoves = Number(turn) || 0
  return halfMoves > 0 ? Math.ceil(halfMoves / 2) : 0
}
