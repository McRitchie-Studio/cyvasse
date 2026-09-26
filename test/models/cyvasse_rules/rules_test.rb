require "test_helper"

# [unit] The Ruby rules port on its own terms: the board, the setup string
# codec, and the two properties online play leans on (the board turned round
# is the same game; a turn is all or nothing).
class CyvasseRules::RulesTest < ActiveSupport::TestCase
  Game = CyvasseRules::Game
  Board = CyvasseRules::Board
  RECORD = JSON.parse(Rails.root.join("test/fixtures/files/rules_agreement.json").read)

  Piece = Struct.new(:team, :type)
  Position = Struct.new(:pieces) do
    def piece_at(hex) = pieces[hex]
  end

  def lineup(hexes)
    Game.format((1..19).zip(hexes))
  end

  test "the board has 91 hexes with six neighbours inside and fewer on the rim" do
    assert_equal 91, Board::HEXES.size
    assert_equal 6, Board.neighbors(Board.hex_at(46)).size
    assert_equal 3, Board.neighbors(Board.hex_at(1)).size
    assert(Board::HEXES.all? { |hex| Board.neighbors(hex).all? { |n| Board.neighbors(n).include?(hex) } }, "neighbours are mutual")
  end

  # The away player sees the board turned round (hex 92 - n) with the teams
  # swapped. Their browser computes moves in that frame and the server in the
  # home frame, so the two must agree on every recorded position.
  test "the rules are the same game with the board turned round" do
    RECORD.fetch("positions").each do |record|
      turned = Position.new(record.fetch("units").to_h { |team, index, hex| [ Board.mirror(hex), Piece.new(1 - team, CyvasseRules::Units.type_at(index)) ] })
      record.fetch("actions").each do |hex, jump, moves, attacks|
        actions = CyvasseRules::Rules.legal_actions(turned, Board.mirror(hex), jump:)
        assert_equal moves.map { Board.mirror(_1) }.sort, actions.moves.sort
        assert_equal attacks.map { Board.mirror(_1) }.sort, actions.attacks.sort
      end
    end
  end

  test "a setup must place every unit once on the player's own five rows" do
    good = lineup((52..70).to_a)
    assert_equal 19, Game.parse_lineup!(good).size

    assert_raises(Game::IllegalMove) { Game.parse_lineup!(lineup((52..69).to_a + [ 40 ])) }
    assert_raises(Game::IllegalMove) { Game.parse_lineup!(lineup((52..69).to_a + [ 52 ])) }
    assert_raises(Game::IllegalMove) { Game.parse_lineup!(good.sub("19:70|", "")) }
    assert_raises(Game::IllegalMove) { Game.parse_lineup!(good.sub("19:70|", "18:70|")) }
    assert_raises(Game::IllegalMove) { Game.parse_lineup!("1:x|") }
    assert_raises(Game::IllegalMove) { Game.parse_lineup!(nil) }
  end

  test "the away lineup is stored turned into the home frame" do
    pairs = Game.mirror_lineup(Game.parse_lineup!(lineup((52..70).to_a)))
    assert(pairs.all? { |_, hex| Board::AWAY_ZONE.cover?(hex) })
  end

  test "the legacy location codes round-trip: hex, g<team> captured, lDock unplaced" do
    home = "1:52|2:g1|3:lDock|"
    game = Game.new(home:, away: "")
    assert_equal home, game.position(Game::HOME)
  end

  test "the king nearer the middle row moves first; a tie is the coin's" do
    home = (52..70).to_a
    home[16] = 52 # the king (army index 17) at the back: row 7
    away = (1..19).map { Board.mirror(_1) }.reverse
    game = Game.new(home: lineup(home), away: lineup(away.map { Board.mirror(_1) }))
    king_rows = [ Game::HOME, Game::AWAY ].map { |team| Board.hex_at(game.units.find { |u| u.team == team && u.type.king? }.hex).y }
    game.start!(coin: -> { flunk "no tie here" })
    expected = (6 - king_rows[1]).abs > (6 - king_rows[0]).abs ? Game::HOME : Game::AWAY
    assert_equal expected, game.offense
    assert_equal 1, game.turn

    tie = Game.new(home: lineup((52..70).to_a), away: lineup((52..70).map { Board.mirror(_1) }))
    tie.start!(coin: -> { Game::AWAY })
    assert_equal Game::AWAY, tie.offense
  end

  test "an illegal step leaves the game untouched" do
    record = RECORD.fetch("games").first
    game = Game.new(home: record.fetch("home"), away: record.fetch("away"))
    game.start!(coin: -> { record.fetch("first") })
    before = [ game.position(0), game.position(1), game.offense, game.turn ]

    mover = game.units.find { |u| u.team == game.offense && u.alive? && !u.type.mountain? && !u.type.cavalry? }
    assert_raises(Game::IllegalMove) { game.play!([ [ mover.hex, mover.hex ] ]) }
    enemy = game.units.find { |u| u.team != game.offense && u.alive? }
    assert_raises(Game::IllegalMove) { game.play!([ [ enemy.hex, 46 ] ]) }
    assert_raises(Game::IllegalMove) { game.play!([]) }
    assert_raises(Game::IllegalMove) { game.play!([ [ 1, 2 ], [ 3, 4 ], [ 5, 6 ] ]) }
    assert_raises(Game::IllegalMove) { game.play!([ [ "1", 2 ] ]) }
    assert_equal before, [ game.position(0), game.position(1), game.offense, game.turn ]
  end

  test "a cavalry unit with a second jump must take it, and a plain move is one step" do
    record = RECORD.fetch("games").find { |g| g.fetch("turns").any? { |t| t.fetch("steps").size == 2 } }
    game = Game.new(home: record.fetch("home"), away: record.fetch("away"))
    game.start!(coin: -> { record.fetch("first") })
    record.fetch("turns").each do |turn|
      steps = turn.fetch("steps")
      if steps.size == 2
        snapshot = [ game.position(0), game.position(1) ]
        assert_raises(Game::IllegalMove, "the first jump alone") { game.play!(steps.take(1)) }
        assert_equal snapshot, [ game.position(0), game.position(1) ]
        game.play!(steps)
        break
      end
      assert_raises(Game::IllegalMove, "a second step on a plain move") { game.play!(steps + [ steps.first.reverse ]) } unless steps.size == 2
      game.play!(steps)
    end
  end

  # The horse jumps 46 -> 49 and has a second jump from 49. A client that
  # names any other hex as the second step's start (another of its own units,
  # an enemy, the hex the horse just left) is refused, and nothing moves: the
  # server never lets a second jump teleport the horse from elsewhere. The
  # same position as game_test.js "cavalry jumps twice with the same unit".
  test "a cavalry unit's second jump must start where its first ended" do
    game = Game.new(home: boxed(1, 8 => 46, 17 => 91), away: boxed(0, 17 => 1, 1 => 5), offense: Game::HOME, turn: 3)
    assert_raises(Game::IllegalMove, "the horse owes a second jump from 49") { game.play!([ [ 46, 49 ] ]) }
    before = [ game.position(0), game.position(1), game.offense, game.turn ]

    { 91 => "the home king", 5 => "an away rabble", 46 => "the hex the horse left" }.each do |from2, what|
      to2 = game.legal_actions(from2, jump: 2).moves.first || 51
      assert_raises(Game::IllegalMove, "second step from #{what}") { game.play!([ [ 46, 49 ], [ from2, to2 ] ]) }
      assert_equal before, [ game.position(0), game.position(1), game.offense, game.turn ], "#{what}: nothing moved"
    end

    result = game.play!([ [ 46, 49 ], [ 49, 51 ] ])
    assert_equal [ 49, 51 ], result.last_move
    assert_equal 46, result.util_move, "the first jump's start stays marked"
    assert_equal 51, game.units.find { |u| u.team == Game::HOME && u.index == 8 }.hex
  end

  # A king in the corner behind its own two mountains and its trebuchet, the
  # rest of the army captured: none of the four can act (the trebuchet has no
  # move and nothing in range).
  def boxed(team, spots)
    Game.format((1..19).map { |index| [ index, spots.fetch(index, "g#{team}") ] })
  end

  BOXED_AWAY = { 14 => 8, 17 => 1, 18 => 2, 19 => 7 }.freeze
  BOXED_HOME = BOXED_AWAY.transform_values { Board.mirror(_1) }.freeze

  test "a side with no move passes the turn back" do
    assert_equal [ 2, 7, 8 ], Board.neighbors(Board.hex_at(1)).map(&:index).sort
    game = Game.new(home: boxed(1, 17 => 80), away: boxed(0, BOXED_AWAY), offense: Game::HOME, turn: 3)
    step = game.legal_actions(80).moves.first
    result = game.play!([ [ 80, step ] ])

    assert result.passed, "the away side cannot move: the turn passes"
    assert_not result.over
    assert_equal Game::HOME, game.offense
    assert_equal 5, game.turn, "the pass counts as a turn"
    assert_equal step, game.piece_at(step).hex
  end

  test "when neither side can move the game is drawn" do
    game = Game.new(home: boxed(1, BOXED_HOME), away: boxed(0, BOXED_AWAY))
    result = game.start!(coin: -> { Game::HOME })

    assert result.passed
    assert result.over
    assert_nil game.winner
    assert_equal :over, game.phase
  end
end
