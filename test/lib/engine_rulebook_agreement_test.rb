require "test_helper"

# [unit] The /rules reference card (Rulebook) and the game engine
# (app/javascript/cyvasse/units.js) state the same unit numbers. They live in
# two languages, so this reads the engine's table as text: a stat changed in
# one place and not the other goes red here instead of on the rules page.
class EngineRulebookAgreementTest < ActiveSupport::TestCase
  ENGINE = Rails.root.join("app/javascript/cyvasse/units.js")
  ROW = /^\s*(\w+): unit\("(\w+)", "([^"]+)", "(\w+)", \{ attack: (\d+), defence: (\d+), moveRange: (\d+), attackRange: (\d+), flank: \d+, trump: \[([^\]]*)\] \}\)/

  def engine_units
    @engine_units ||= ENGINE.read.scan(ROW).to_h do |_key, codename, name, rank, attack, defence, move, range, trump|
      [ codename, { name:, rank:, attack: attack.to_i, defence: defence.to_i, move: move.to_i, range: range.to_i,
                    trump: trump.scan(/"(\w+)"/).flatten } ]
    end
  end

  def rulebook_units
    Rulebook.classes.flat_map(&:units).index_by(&:slug)
  end

  test "the engine defines every piece" do
    assert_equal Piece.all.map(&:slug).sort, engine_units.keys.sort
  end

  test "names, strength, movement, range and trumps agree" do
    rulebook_units.except("mountain").each do |slug, card|
      unit = engine_units.fetch(slug)
      assert_equal card.name, unit[:name], slug
      assert_equal card.strength, unit[:attack].to_s, "#{slug} strength"
      assert_equal card.range.to_i, unit[:range], "#{slug} range (nil on the card is 0 in the engine)"
      trumps = unit[:trump].map { |codename| Piece.all.find { |p| p.slug == codename }.name }
      assert_equal card.trumps, trumps, "#{slug} trumps"

      movement = case unit[:rank]
      when "cavalry" then "#{unit[:move]} + 2"
      when "unique" then slug == "dragon" ? "Moves in a straight line" : unit[:move].to_s
      else unit[:move].to_s
      end
      assert_equal card.movement, movement, "#{slug} movement"
    end
  end
end
