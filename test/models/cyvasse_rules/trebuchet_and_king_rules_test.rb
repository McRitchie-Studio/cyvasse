require "test_helper"

# [unit] The rule changes of September 29, 2026 on the server
# (app/models/cyvasse_rules), the rules online play is validated by:
#   - the trebuchet reaches four hexes and trumps the dragon (it trumped the
#     spearman and the light horse too until the new stats of that evening,
#     cyvasse-stats-and-trumps-v3), but never takes the king;
#   - no mountain, of either side, lets its shot through;
#   - the king trumps the dragon, so it takes a dragon within its move.
# test/javascript/rules_test.js holds the browser engine to the same cases.
#
# Hex numbers are the legacy data-hexIndex: 46 is the middle of the board,
# 47 48 49 50 51 run to its right along the middle row, 45 44 43 42 to its left.
class CyvasseRules::TrebuchetAndKingRulesTest < ActiveSupport::TestCase
  Rules = CyvasseRules::Rules
  Board = CyvasseRules::Board
  Units = CyvasseRules::Units
  Game = CyvasseRules::Game
  Bot = CyvasseRules::Bot
  ALLY = 1
  ENEMY = 0

  Piece = Struct.new(:team, :type)
  Position = Struct.new(:pieces) do
    def piece_at(hex) = pieces[hex]
  end

  def position(layout)
    Position.new(layout.to_h { |hex, (team, codename)| [ hex, Piece.new(team, Units::TYPES.fetch(codename)) ] })
  end

  def attacks(layout, origin = 46)
    Rules.legal_actions(position(layout), origin).attacks
  end

  def distance(a, b)
    cube = ->(hex) { r = hex.y - 6; q = hex.x - 1 - [ 0, r ].min - 5; [ q, r, -q - r ] }
    cube.(Board.hex_at(a)).zip(cube.(Board.hex_at(b))).map { |x, y| (x - y).abs }.max
  end

  def disc(origin, radius)
    Board::HEXES.map(&:index).select { |i| i != origin && distance(origin, i) <= radius }
  end

  test "the trebuchet's numbers: range four, trumps only the dragon" do
    trebuchet = Units::TYPES.fetch("trebuchet")
    assert_equal 4, trebuchet.attack_range
    assert_equal 0, trebuchet.move_range
    assert_equal %w[dragon], trebuchet.trump
    assert_equal %w[dragon], Units::TYPES.fetch("king").trump
    assert_equal 3, Units::TYPES.fetch("catapult").attack_range, "the catapult is unchanged"
    assert_equal 2, Units::TYPES.fetch("crossbowman").attack_range, "the crossbowman is unchanged"
  end

  test "a trebuchet reaches an enemy four hexes away, and not five" do
    assert_equal [ 50 ], attacks(46 => [ ALLY, "trebuchet" ], 50 => [ ENEMY, "rabble" ])
    assert_equal [ 42 ], attacks(46 => [ ALLY, "trebuchet" ], 42 => [ ENEMY, "rabble" ])
    assert_equal [], attacks(46 => [ ALLY, "trebuchet" ], 51 => [ ENEMY, "rabble" ])

    in_reach = disc(46, 4).select { |hex| attacks(46 => [ ALLY, "trebuchet" ], hex => [ ENEMY, "rabble" ]) == [ hex ] }
    assert_equal disc(46, 4), in_reach, "every hex within four, on an open board"
  end

  test "a trebuchet takes a dragon, near and at four, and no longer a spearman or a light horse" do
    [ 47, 50 ].each do |hex|
      assert_equal [ hex ], attacks(46 => [ ALLY, "trebuchet" ], hex => [ ENEMY, "dragon" ]), "dragon on #{hex}"
      assert_equal [], attacks(46 => [ ALLY, "trebuchet" ], hex => [ ENEMY, "spearman" ]), "spearman (3) on #{hex}"
      assert_equal [], attacks(46 => [ ALLY, "trebuchet" ], hex => [ ENEMY, "lighthorse" ]), "light horse (2) on #{hex}"
    end
  end

  test "a trebuchet cannot take the king anywhere in its reach" do
    disc(46, 4).each do |hex|
      assert_equal [], attacks(46 => [ ALLY, "trebuchet" ], hex => [ ENEMY, "king" ]), "king on #{hex}"
    end
  end

  test "a mountain of either side blocks the trebuchet's shot" do
    assert_equal [ 50 ], attacks(46 => [ ALLY, "trebuchet" ], 50 => [ ENEMY, "rabble" ]), "control: in reach"
    [ ALLY, ENEMY ].each do |side|
      [ 47, 48, 49 ].each do |mountain|
        layout = { 46 => [ ALLY, "trebuchet" ], mountain => [ side, "mountain" ], 50 => [ ENEMY, "rabble" ] }
        assert_equal [], attacks(layout), "a #{side == ALLY ? 'friendly' : 'enemy'} mountain on #{mountain}"
      end
    end
  end

  test "a hex whose every shortest path crosses a mountain is out of the trebuchet's reach" do
    rng = Random.new(29)
    kinds = %w[rabble spearman lighthorse dragon crossbowman catapult]
    sheltered = 0
    120.times do |trial|
      layout = {}
      Board::HEXES.each do |hex|
        roll = rng.rand
        layout[hex.index] = [ rng.rand(2), "mountain" ] if roll < 0.12
        layout[hex.index] = [ ENEMY, kinds.sample(random: rng) ] if roll.between?(0.12, 0.4)
      end
      origin = rng.rand(1..91)
      layout[origin] = [ ALLY, "trebuchet" ]
      board = position(layout)

      clear = Set[origin]
      (1..4).each do |d|
        Board::HEXES.each do |hex|
          next unless distance(origin, hex.index) == d
          next if board.piece_at(hex.index)&.type&.mountain?

          clear << hex.index if Board.neighbors(hex).any? { |n| clear.include?(n.index) && distance(origin, n.index) == d - 1 }
        end
      end

      shots = Rules.legal_actions(board, origin).attacks
      shots.each { |to| assert clear.include?(to), "trial #{trial}: #{origin} fires over a mountain at #{to}" }
      sheltered += disc(origin, 4).count { |hex| !clear.include?(hex) && board.piece_at(hex) && !board.piece_at(hex).type.mountain? }
    end
    assert_operator sheltered, :>, 20, "mountains sheltered targets often enough to test the rule"
  end

  test "a king takes an adjacent dragon, or one two hexes away through an empty hex" do
    assert_equal [ 47 ], attacks(46 => [ ALLY, "king" ], 47 => [ ENEMY, "dragon" ])
    assert_equal [ 48 ], attacks(46 => [ ALLY, "king" ], 48 => [ ENEMY, "dragon" ])
    assert_equal [], attacks(46 => [ ALLY, "king" ], 49 => [ ENEMY, "dragon" ]), "beyond the king's move"
  end

  test "the dragon can still take the king" do
    assert_equal [ 47 ], attacks(46 => [ ALLY, "dragon" ], 47 => [ ENEMY, "king" ])
  end

  # A whole online turn: the server accepts the new captures and the bot takes them.
  def boxed(team, spots)
    Game.format((1..19).map { |index| [ index, spots.fetch(index, "g#{team}") ] })
  end

  test "the server plays a king's capture of a dragon, and the bot chooses it" do
    # Home king (17) on 46; away dragon (16) on 47, away king far off on 1.
    game = Game.new(home: boxed(1, 17 => 46), away: boxed(0, 16 => 47, 17 => 1), offense: Game::HOME, turn: 5)
    assert_equal [ [ 46, 47 ] ], Bot.choose_turn(game, rng: Random.new(1))
    result = game.play!([ [ 46, 47 ] ])
    assert_equal "dragon", result.captured.first.type.codename
    assert_equal 47, game.units.find { |u| u.team == Game::HOME && u.type.king? }.hex
  end

  test "the server plays a trebuchet's four-hex shot at a dragon, and the trebuchet stays put" do
    # Home trebuchet (14) on 46; away dragon (16) on 50; the kings far apart.
    game = Game.new(home: boxed(1, 14 => 46, 17 => 91), away: boxed(0, 16 => 50, 17 => 1), offense: Game::HOME, turn: 5)
    assert_equal [ [ 46, 50 ] ], Bot.choose_turn(game, rng: Random.new(1))
    result = game.play!([ [ 46, 50 ] ])
    assert_equal "dragon", result.captured.first.type.codename
    assert_equal 46, game.units.find { |u| u.team == Game::HOME && u.index == 14 }.hex
  end
end
