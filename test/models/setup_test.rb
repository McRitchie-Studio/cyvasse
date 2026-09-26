require "test_helper"

# [unit] Setup, a saved army lineup (piece 10b): what a new one must be, the
# newest in a slot winning, saving over a slot, and reading a legacy army
# string as the board places it.
class SetupTest < ActiveSupport::TestCase
  setup { @player = User.create!(email: "lineups@example.test", name: "Lineups") }

  test "a new lineup needs a name of at most 20 characters, a slot of 1 to 3, and a whole army on the player's rows" do
    assert Setup.new(valid_attributes).valid?
    assert_invalid name: " "
    assert_invalid name: "x" * 21
    assert_invalid button_position: 0
    assert_invalid button_position: 4
    assert_invalid units_position: army(52..69), message: /place all 19 units/
    assert_invalid units_position: army(1..19), message: /five rows/
    assert_invalid units_position: army([ *52..69, 52 ]), message: /share a hex/
  end

  test "legacy rows are written without the new-lineup rules and still update" do
    legacy = Setup.insert_all!([ { user_id: @player.id, name: "", units_position: army(52..69), button_position: 7,
                                   created_at: Time.current, updated_at: Time.current } ])
    setup = Setup.find(legacy.rows.first.first)
    assert setup.update(updated_at: 1.day.from_now), "an update is not held to the rules for new lineups"
    assert_nil setup.lineup
  end

  test "each slot shows its newest lineup, and a visitor has none" do
    old = create(slot: 2, name: "Old", at: 2.days.ago)
    newer = create(slot: 2, name: "Newer", at: 1.day.ago)
    create(slot: 1, name: "First")
    Setup.create!(user: User.create!(email: "other@example.test", name: "Other"), button_position: 3, name: "Theirs",
                  units_position: army(52..70))

    slots = Setup.slots_for(@player)
    assert_equal [ 1, 2, 3 ], slots.keys
    assert_equal [ "First", "Newer", nil ], slots.values.map { |s| s&.name }
    refute_equal old, slots[2]
    assert_equal newer, slots[2]
    assert_equal [ nil, nil, nil ], Setup.slots_for(nil).values
  end

  test "saving to a slot replaces every lineup it held, and leaves the other slots alone" do
    create(slot: 2, name: "Old", at: 2.days.ago)
    create(slot: 2, name: "Older", at: 3.days.ago)
    keep = create(slot: 1, name: "Keep")

    saved = Setup.save_slot!(@player, slot: 2, name: "  Fresh  ", lineup: army(73..91))
    assert_equal [ "Fresh" ], @player.setups.where(button_position: 2).pluck(:name)
    assert_equal army(73..91), saved.lineup
    assert Setup.exists?(keep.id)
  end

  test "an invalid save keeps what the slot held" do
    create(slot: 2, name: "Old")
    assert_raises(ActiveRecord::RecordInvalid) { Setup.save_slot!(@player, slot: 2, name: "Bad", lineup: army(1..19)) }
    assert_equal [ "Old" ], @player.setups.pluck(:name)
  end

  test "the lineup is the army sorted by unit; one saved from the away seat is turned round" do
    shuffled = army(52..70).split("|").reverse.map { |pair| "#{pair}|" }.join
    assert_equal army(52..70), Setup.new(units_position: shuffled).lineup
    assert_equal army((73..91).to_a.reverse), Setup.new(units_position: army(1..19)).lineup
    assert_nil Setup.new(units_position: "1:52|junk|").lineup
    assert_nil Setup.new(units_position: nil).lineup
  end

  test "a player's lineups go with them" do
    create(slot: 1, name: "Mine")
    assert_difference -> { Setup.count }, -1 do
      @player.destroy!
    end
  end

  private

  def valid_attributes
    { user: @player, name: "Wall", button_position: 1, units_position: army(52..70) }
  end

  def assert_invalid(message: nil, **overrides)
    setup = Setup.new(valid_attributes.merge(overrides))
    refute setup.valid?, overrides.inspect
    assert_match message, setup.errors.full_messages.to_sentence if message
  end

  def create(slot:, name:, at: Time.current)
    Setup.create!(user: @player, button_position: slot, name: name, units_position: army(52..70), created_at: at)
  end

  def army(hexes) = hexes.to_a.each_with_index.map { |hex, i| "#{i + 1}:#{hex}|" }.join
end
