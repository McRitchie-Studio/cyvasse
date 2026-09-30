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

  # The stats carry the April 14, 2015 changes the page lists, except where
  # September 29, 2026 overrode them: crossbowmen trump nothing now.
  test "the stats reflect the 2015 rule changes that still stand" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)

    assert_not_includes units["spearman"].trumps, "Heavy Horse"
    assert_equal "3", units["catapult"].strength
    assert_equal "0", units["trebuchet"].movement
    assert_includes units["catapult"].trumps, "Dragon"
  end

  test "the stats reflect the September 2026 rule changes" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)

    assert_equal 4, units["trebuchet"].range
    assert_equal [ "Dragon" ], units["trebuchet"].trumps
    assert_equal [ "Dragon" ], units["king"].trumps
    assert_equal "2", units["elephant"].movement
    assert_includes Rulebook::CHANGES_2026, "Elephants now move 2."
    assert_equal 8, Rulebook::CHANGES_2026.size
  end

  # Alex's new stats (task cyvasse-stats-and-trumps-v3): Strength, trumps and
  # the two cavalry jumps, as the unit cards print them.
  test "the stats reflect the new stats and trumps of September 29, 2026" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)
    strengths = units.except("mountain").transform_values(&:strength)
    assert_equal({ "rabble" => "1", "spearman" => "3", "elephant" => "4", "lighthorse" => "2", "heavyhorse" => "3",
                   "crossbowman" => "2", "catapult" => "3", "trebuchet" => "1", "dragon" => "5", "king" => "2" }, strengths)
    trumps = units.transform_values(&:trumps).reject { |_, list| list.empty? }
    assert_equal({ "rabble" => [ "King" ], "catapult" => [ "Dragon" ], "trebuchet" => [ "Dragon" ], "king" => [ "Dragon" ] }, trumps)
    assert_equal "1", units["catapult"].movement
    assert_equal 1, Rulebook::RANGE_DEFENCE
    assert(Rulebook::CHANGES_2026.any? { |change| change.start_with?("Trumps now work on offense only") })
  end

  test "trump_list joins with and, and shows a dash for none" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)

    assert_equal "King", Rulebook.trump_list(units["rabble"])
    assert_equal "Dragon", Rulebook.trump_list(units["trebuchet"])
    assert_equal "—", Rulebook.trump_list(units["spearman"])
    three = Rulebook::Unit.new(piece: Piece.all.first, movement: "1", strength: "1", range: nil, trumps: %w[Dragon Spearman Elephant])
    assert_equal "Dragon, Spearman and Elephant", Rulebook.trump_list(three)
    two = Rulebook::Unit.new(piece: Piece.all.first, movement: "1", strength: "1", range: nil, trumps: %w[Elephant Dragon])
    assert_equal "Elephant and Dragon", Rulebook.trump_list(two)
  end

  test "each cavalry unit carries its own two jumps: light horse 4 + 1, heavy horse 3 + 1" do
    assert_equal [ 4, 1 ], Rulebook.fetch("lighthorse").jumps
    assert_equal [ 3, 1 ], Rulebook.fetch("heavyhorse").jumps
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
