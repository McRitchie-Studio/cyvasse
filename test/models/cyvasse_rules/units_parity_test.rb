require "test_helper"

# [unit] The server's unit table (CyvasseRules::Units) equals the browser's
# (app/javascript/cyvasse/units.js) row for row: every unit's name, rank,
# attack, defence, move range, cavalry second jump, attack range and trumps,
# and the army order; and the computer's kill priority (ai.js) is bot.rb's.
# The rules record (js_agreement_test.rb) catches a drift only where a
# recorded position happens to exercise it; this reads the JS table itself,
# so a number changed in one language and not the other goes red here.
class CyvasseRules::UnitsParityTest < ActiveSupport::TestCase
  ENGINE = Rails.root.join("app/javascript/cyvasse/units.js")
  AI = Rails.root.join("app/javascript/cyvasse/ai.js")
  ROW = /^\s*(\w+): unit\("(\w+)", "([^"]+)", "(\w+)", \{ attack: (\d+), defence: (\d+), moveRange: (\d+), secondJump: (\d+), attackRange: (\d+), flank: \d+, trump: \[([^\]]*)\] \}\)/

  def js_units
    @js_units ||= ENGINE.read.scan(ROW).to_h do |key, codename, name, rank, attack, defence, move, second, range, trump|
      assert_equal key, codename, "units.js keys #{codename} by its codename"
      [ codename, { name:, rank:, attack: attack.to_i, defence: defence.to_i, move_range: move.to_i,
                    second_jump: second.to_i, attack_range: range.to_i, trump: trump.scan(/"(\w+)"/).flatten } ]
    end
  end

  def js_army
    ENGINE.read[/export const ARMY = Object\.freeze\(\[(.*?)\]\)/m, 1].scan(/"(\w+)"/).flatten
  end

  test "both tables define the same eleven units" do
    assert_equal 11, js_units.size, "every units.js row parsed"
    assert_equal CyvasseRules::Units::TYPES.keys.sort, js_units.keys.sort
  end

  test "every unit's numbers agree between Ruby and JavaScript" do
    CyvasseRules::Units::TYPES.each do |codename, type|
      ruby = type.to_h.slice(:name, :rank, :attack, :defence, :move_range, :second_jump, :attack_range, :trump)
      assert_equal js_units.fetch(codename), ruby, codename
    end
  end

  test "the army is the same nineteen units in the same order" do
    assert_equal 19, js_army.size
    assert_equal CyvasseRules::Units::ARMY, js_army
  end

  test "the server's computer ranks captures as the browser's does" do
    js = AI.read[/export const KILL_PRIORITY = Object\.freeze\(\[(.*?)\]\)/m, 1].scan(/"(\w+)"/).flatten
    assert_equal 10, js.size
    assert_equal CyvasseRules::Bot::KILL_PRIORITY, js
  end

  # Alex's table of September 29, 2026 (task cyvasse-stats-and-trumps-v3,
  # with his 21:48 MDT change: the spearman trumps nothing). Strength is
  # attack; defence equals it, except the range units, which defend at 1.
  # [codename, move, second jump, strength, range, trumps]
  ALEX_TABLE = [
    [ "rabble", 3, 0, 1, 0, [ "king" ] ],
    [ "trebuchet", 0, 0, 1, 4, [ "dragon" ] ],
    [ "king", 2, 0, 2, 0, [ "dragon" ] ],
    [ "lighthorse", 4, 1, 2, 0, [] ],
    [ "crossbowman", 1, 0, 2, 2, [] ],
    [ "spearman", 2, 0, 3, 0, [] ],
    [ "heavyhorse", 3, 1, 3, 0, [] ],
    [ "catapult", 1, 0, 3, 3, [ "dragon" ] ],
    [ "elephant", 2, 0, 4, 0, [] ],
    [ "dragon", 10, 0, 5, 0, [] ]
  ].freeze

  test "the server's table is Alex's new stats table" do
    ALEX_TABLE.each do |codename, move, second, strength, range, trump|
      type = CyvasseRules::Units::TYPES.fetch(codename)
      defence = type.range? ? 1 : strength
      assert_equal [ move, second, strength, defence, range, trump ],
                   [ type.move_range, type.second_jump, type.attack, type.defence, type.attack_range, type.trump ], codename
    end
    mountain = CyvasseRules::Units::TYPES.fetch("mountain")
    assert_equal [ 0, 0 ], [ mountain.move_range, mountain.second_jump ], "the mountain is unchanged: immovable"
  end
end
