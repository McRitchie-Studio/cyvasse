require "test_helper"

# [unit] The rulebook's reference data, ported from the legacy unit models.
class RulebookTest < ActiveSupport::TestCase
  test "the four classes hold every piece exactly once, in the original order" do
    assert_equal %w[Vanguard Cavalry Range Unique], Rulebook.classes.map(&:name)

    slugs = Rulebook.classes.flat_map(&:units).map(&:slug)
    assert_equal Piece.all.map(&:slug).sort, slugs.sort
    assert_equal %w[rabble spearman elephant lighthorse heavyhorse crossbowman catapult trebuchet dragon king mountain], slugs
  end

  test "only the Range class carries a range" do
    Rulebook.classes.each do |unit_class|
      unit_class.units.each do |unit|
        assert_equal unit_class.name == "Range", !unit.range.nil?, "#{unit.name} range"
      end
    end
  end

  test "every trump names a real piece" do
    names = Piece.all.map(&:name)

    Rulebook.classes.flat_map(&:units).flat_map(&:trumps).each do |trump|
      assert_includes names, trump
    end
  end

  # The stats already carry the April 14, 2015 changes the page lists.
  test "the stats reflect the 2015 rule changes" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)

    assert_not_includes units["spearman"].trumps, "Heavy Horse"
    assert_equal "3", units["catapult"].strength
    assert_equal "0", units["trebuchet"].movement
    assert_includes units["crossbowman"].trumps, "Elephant"
    assert_includes units["catapult"].trumps, "Dragon"
  end

  test "the stats reflect the September 2026 rule changes" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)

    assert_equal 4, units["trebuchet"].range
    assert_equal [ "Dragon", "Spearman", "Light Horse" ], units["trebuchet"].trumps
    assert_equal [ "Dragon" ], units["king"].trumps
    assert_equal "2", units["elephant"].movement
    assert_includes Rulebook::CHANGES_2026, "Elephants now move 2."
    assert_equal 4, Rulebook::CHANGES_2026.size
  end

  # The unit cards draw each trump as that piece's art, so every trump name
  # must resolve to a Piece, in the rulebook's order.
  test "trumped_pieces resolves each trump to its piece, and is empty for none" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)

    assert_equal %w[lighthorse], units["spearman"].trumped_pieces.map(&:slug)
    assert_equal %w[dragon spearman lighthorse], units["trebuchet"].trumped_pieces.map(&:slug)
    assert_equal [], units["rabble"].trumped_pieces
    units.each_value { |unit| assert_equal unit.trumps, unit.trumped_pieces.map(&:name), unit.slug }
    stray = Rulebook::Unit.new(piece: Piece.all.first, movement: "1", strength: "1", range: nil, trumps: [ "Wyvern" ])
    assert_raises(KeyError) { stray.trumped_pieces }
  end

  test "each cavalry unit carries its own first jump and the shared second" do
    assert_equal [ 3, Rulebook::CAVALRY_SECOND_JUMP ], Rulebook.fetch("lighthorse").jumps
    assert_equal [ 2, Rulebook::CAVALRY_SECOND_JUMP ], Rulebook.fetch("heavyhorse").jumps
    assert_nil Rulebook.fetch("rabble").jumps
    assert_nil Rulebook.fetch("dragon").jumps
  end

  test "fetch and class_of find a unit by slug" do
    assert_equal "Trebuchet", Rulebook.fetch("trebuchet").name
    assert_equal "Range", Rulebook.class_of(Rulebook.fetch("trebuchet"))
    assert_raises(KeyError) { Rulebook.fetch("wizard") }
  end

  # Counted from the engine's army list, so the page cannot say "10 military
  # pieces" again (production audit #6).
  test "the army is 19 pieces: 17 units of 10 kinds and 2 mountains" do
    assert_equal 19, Rulebook.army_size
    assert_equal 17, Rulebook.army_unit_count
    assert_equal 10, Rulebook.unit_kind_count
    assert_equal 2, Rulebook.mountain_count
  end
end
