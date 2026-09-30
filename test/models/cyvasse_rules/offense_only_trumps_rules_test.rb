require "test_helper"

# [unit] Rule changes of September 29, 2026 on the server (Alex, task
# cyvasse-stats-and-trumps-v3): strength is every unit's attack, the range
# units defend at 1, a trump works on offense only (the attacker takes a unit
# it trumps; the defender's trumps never protect it), and the horses jump
# 4 + 1 and 3 + 1. test/javascript/rules_test.js holds the browser engine to
# the same cases.
#
# Hex numbers are the legacy data-hexIndex: 46 is the middle of the board,
# 47 48 49 50 51 run to its right along the middle row.
class CyvasseRules::OffenseOnlyTrumpsRulesTest < ActiveSupport::TestCase
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

  def actions(layout, origin = 46, jump: 1)
    Rules.legal_actions(position(layout), origin, jump:)
  end

  def attacks(layout, origin = 46) = actions(layout, origin).attacks

  def distance(a, b)
    cube = ->(hex) { r = hex.y - 6; q = hex.x - 1 - [ 0, r ].min - 5; [ q, r, -q - r ] }
    cube.(Board.hex_at(a)).zip(cube.(Board.hex_at(b))).map { |x, y| (x - y).abs }.max
  end

  def disc(origin, radius)
    Board::HEXES.map(&:index).select { |i| i != origin && distance(origin, i) <= radius }
  end

  test "a trumped defender still wins when it attacks: dragon and trebuchet each take the other" do
    assert_equal [ 50 ], attacks(46 => [ ALLY, "dragon" ], 50 => [ ENEMY, "trebuchet" ]), "the dragon attacks the trebuchet"
    assert_equal [ 50 ], attacks(46 => [ ALLY, "trebuchet" ], 50 => [ ENEMY, "dragon" ]), "the trebuchet attacks the dragon"
    assert_equal [ 48 ], attacks(46 => [ ALLY, "dragon" ], 48 => [ ENEMY, "catapult" ]), "the dragon takes the catapult"
    assert_not_includes actions({ 46 => [ ALLY, "dragon" ], 48 => [ ENEMY, "catapult" ] }).moves, 49, "and its flight ends there"
  end

  test "the rabble takes the king it trumps, and the king still takes the rabble" do
    assert_equal [ 47 ], attacks(46 => [ ALLY, "rabble" ], 47 => [ ENEMY, "king" ])
    assert_equal [ 47 ], attacks(46 => [ ALLY, "king" ], 47 => [ ENEMY, "rabble" ])
    assert_equal [], attacks(46 => [ ALLY, "rabble" ], 47 => [ ENEMY, "lighthorse" ]), "control: an untrumped 2"
  end

  test "a range unit defends at 1: any unit takes it" do
    %w[crossbowman trebuchet catapult].each do |shooter|
      assert_equal 1, Units::TYPES.fetch(shooter).defence, shooter
      assert_equal [ 47 ], attacks(46 => [ ALLY, "rabble" ], 47 => [ ENEMY, shooter ]), "a rabble takes the #{shooter}"
      assert_equal [ 47 ], attacks(46 => [ ALLY, "elephant" ], 47 => [ ENEMY, shooter ]), "an elephant takes the #{shooter}"
    end
  end

  test "strength decides everything else: the spearman trumps nothing" do
    assert_equal [], attacks(46 => [ ALLY, "spearman" ], 47 => [ ENEMY, "elephant" ])
    assert_equal [ 47 ], attacks(46 => [ ALLY, "spearman" ], 47 => [ ENEMY, "heavyhorse" ]), "3 takes 3"
    assert_equal [], attacks(46 => [ ALLY, "lighthorse" ], 47 => [ ENEMY, "spearman" ]), "2 cannot take 3"
  end

  test "light horse 4 + 1, heavy horse 3 + 1" do
    assert_equal disc(46, 4), actions({ 46 => [ ALLY, "lighthorse" ] }).moves
    assert_equal disc(46, 1), actions({ 46 => [ ALLY, "lighthorse" ] }, jump: 2).moves
    assert_equal disc(46, 3), actions({ 46 => [ ALLY, "heavyhorse" ] }).moves
    assert_equal disc(46, 1), actions({ 46 => [ ALLY, "heavyhorse" ] }, jump: 2).moves
  end

  test "the catapult moves 1" do
    assert_equal disc(46, 1), actions({ 46 => [ ALLY, "catapult" ] }).moves
  end
end
