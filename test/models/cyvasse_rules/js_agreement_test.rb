require "test_helper"

# [unit] The server's rules (app/models/cyvasse_rules) give the browser
# engine's answers (app/javascript/cyvasse) on the recorded positions and
# games in test/fixtures/files/rules_agreement.json. The JS lane
# (test/javascript/agreement_fixture_test.js) proves that file is what the
# engine answers today, so between them a rule changed in one language only
# goes red. This is how "the server validates by the same rules" is kept.
class CyvasseRules::JsAgreementTest < ActiveSupport::TestCase
  RECORD = JSON.parse(Rails.root.join("test/fixtures/files/rules_agreement.json").read)

  Piece = Struct.new(:team, :type)
  Position = Struct.new(:pieces) do
    def piece_at(hex) = pieces[hex]
  end

  # The record writes JavaScript's null for "no mark" and "a draw".
  def assert_same_value(expected, actual, message)
    expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
  end

  test "every recorded unit has the engine's moves and captures, at both jumps" do
    checked = 0
    RECORD.fetch("positions").each_with_index do |record, n|
      pieces = record.fetch("units").to_h { |team, index, hex| [ hex, Piece.new(team, CyvasseRules::Units.type_at(index)) ] }
      position = Position.new(pieces)
      record.fetch("actions").each do |hex, jump, moves, attacks|
        actions = CyvasseRules::Rules.legal_actions(position, hex, jump:)
        assert_equal [ moves, attacks ], [ actions.moves, actions.attacks ],
          "position #{n}: #{pieces[hex].type.codename} on #{hex}, jump #{jump}"
        checked += 1
      end
    end
    assert_operator checked, :>, 1000, "the record is not a handful of cases"
  end

  test "every recorded game replays turn by turn to the engine's state and result" do
    RECORD.fetch("games").each_with_index do |record, g|
      game = CyvasseRules::Game.new(home: record.fetch("home"), away: record.fetch("away"))
      game.start!(coin: -> { record.fetch("first") })
      assert_equal record.fetch("first"), game.offense, "game #{g}: who moves first"

      record.fetch("turns").each_with_index do |turn, t|
        where = "game #{g}, turn #{t}"
        assert_equal turn.fetch("mover"), game.offense, "#{where}: mover"
        result = game.play!(turn.fetch("steps"))
        assert_equal turn.fetch("offense"), game.offense, "#{where}: next to move"
        assert_equal turn.fetch("turn"), game.turn, "#{where}: turn count"
        assert_equal turn.fetch("lastMove"), result.last_move, "#{where}: last move"
        assert_same_value turn.fetch("utilMove"), result.util_move, "#{where}: cavalry mark"
        assert_equal turn.fetch("passed"), result.passed, "#{where}: pass"
        assert_equal turn.fetch("over"), result.over, "#{where}: over"
        assert_equal turn.fetch("dead"), game.units.count { |u| u.status == :dead }, "#{where}: captures"
        assert_same_value turn.fetch("winner"), game.winner, "#{where}: winner" if turn.fetch("over")
      end
    end
  end
end
