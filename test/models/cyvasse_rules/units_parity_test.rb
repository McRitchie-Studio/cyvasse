require "test_helper"

# [unit] The server's unit table (CyvasseRules::Units) equals the browser's
# (app/javascript/cyvasse/units.js) row for row: every unit's name, rank,
# attack, defence, move range, attack range and trumps, and the army order.
# The rules record (js_agreement_test.rb) catches a drift only where a
# recorded position happens to exercise it; this reads the JS table itself,
# so a number changed in one language and not the other goes red here.
class CyvasseRules::UnitsParityTest < ActiveSupport::TestCase
  ENGINE = Rails.root.join("app/javascript/cyvasse/units.js")
  ROW = /^\s*(\w+): unit\("(\w+)", "([^"]+)", "(\w+)", \{ attack: (\d+), defence: (\d+), moveRange: (\d+), attackRange: (\d+), flank: \d+, trump: \[([^\]]*)\] \}\)/

  def js_units
    @js_units ||= ENGINE.read.scan(ROW).to_h do |key, codename, name, rank, attack, defence, move, range, trump|
      assert_equal key, codename, "units.js keys #{codename} by its codename"
      [ codename, { name:, rank:, attack: attack.to_i, defence: defence.to_i, move_range: move.to_i,
                    attack_range: range.to_i, trump: trump.scan(/"(\w+)"/).flatten } ]
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
      ruby = type.to_h.slice(:name, :rank, :attack, :defence, :move_range, :attack_range, :trump)
      assert_equal js_units.fetch(codename), ruby, codename
    end
  end

  test "the army is the same nineteen units in the same order" do
    assert_equal 19, js_army.size
    assert_equal CyvasseRules::Units::ARMY, js_army
  end
end
