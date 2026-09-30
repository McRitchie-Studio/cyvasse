require "test_helper"

# [unit] Match#full_move: the turn a player reads counts full moves (both
# sides' moves are one turn); Match#turn counts half-moves. Mirrors
# cyvasse/turns.js#fullMove (test/javascript/turns_test.js).
class MatchFullMoveTest < ActiveSupport::TestCase
  test "half-moves become full moves" do
    { nil => 0, 0 => 0, 1 => 1, 2 => 1, 3 => 2, 4 => 2, 17 => 9, 18 => 9 }.each do |turn, full|
      assert_equal full, Match.new(turn:).full_move, "turn #{turn.inspect}"
    end
  end
end
