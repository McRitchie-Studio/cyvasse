require "test_helper"

# [unit] Rule change of September 29, 2026 (Alex) on the server, the rules
# online play is validated by: the elephant moves two hexes, not three.
# test/javascript/elephant_test.js holds the browser engine to the same cases.
#
# Hex numbers are the legacy data-hexIndex: 46 is the middle of the board and
# 47 48 49 run to its right along the middle row.
class CyvasseRules::ElephantRulesTest < ActiveSupport::TestCase
  Rules = CyvasseRules::Rules
  Board = CyvasseRules::Board
  Units = CyvasseRules::Units
  ALLY = 1
  ENEMY = 0

  Piece = Struct.new(:team, :type)
  Position = Struct.new(:pieces) do
    def piece_at(hex) = pieces[hex]
  end

  def position(layout)
    Position.new(layout.to_h { |hex, (team, codename)| [ hex, Piece.new(team, Units::TYPES.fetch(codename)) ] })
  end

  def distance(a, b)
    cube = ->(hex) { r = hex.y - 6; q = hex.x - 1 - [ 0, r ].min - 5; [ q, r, -q - r ] }
    cube.(Board.hex_at(a)).zip(cube.(Board.hex_at(b))).map { |x, y| (x - y).abs }.max
  end

  def disc(origin, radius)
    Board::HEXES.map(&:index).select { |i| i != origin && distance(origin, i) <= radius }
  end

  test "the elephant's move range is two" do
    assert_equal 2, Units::TYPES.fetch("elephant").move_range
  end

  test "a lone elephant reaches every hex within two and none at three" do
    moves = Rules.legal_actions(position(46 => [ ALLY, "elephant" ]), 46).moves
    assert_equal disc(46, 2).sort, moves.sort
    assert_includes moves, 48, "two hexes along the row"
    assert_not_includes moves, 49, "three hexes along the row is out of reach"
  end

  test "an elephant captures an enemy two hexes away, and not three" do
    assert_equal [ 48 ], Rules.legal_actions(position(46 => [ ALLY, "elephant" ], 48 => [ ENEMY, "spearman" ]), 46).attacks
    assert_equal [], Rules.legal_actions(position(46 => [ ALLY, "elephant" ], 49 => [ ENEMY, "spearman" ]), 46).attacks
  end
end
