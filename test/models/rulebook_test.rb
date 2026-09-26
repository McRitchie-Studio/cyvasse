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

  test "trump_list joins with and, and shows a dash for none" do
    units = Rulebook.classes.flat_map(&:units).index_by(&:slug)

    assert_equal "Light Horse", Rulebook.trump_list(units["spearman"])
    assert_equal "—", Rulebook.trump_list(units["king"])
    two = Rulebook::Unit.new(piece: Piece.all.first, movement: "1", strength: "1", range: nil, trumps: %w[Elephant Dragon])
    assert_equal "Elephant and Dragon", Rulebook.trump_list(two)
  end
end
