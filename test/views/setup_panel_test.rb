require "test_helper"

# [component] The saved-lineups panel (setups/_panel), rendered alone: a slot
# per button_position wired to the board it sits on, a disabled button for an
# empty slot or one that is not a whole army, an escaped legacy name, and the
# sign-in line for a visitor.
class SetupPanelTest < ActionView::TestCase
  setup { @player = User.create!(email: "panel@example.test", name: "Panel") }

  test "each slot carries its lineup, and the panel is wired to the board it sits on" do
    Setup.create!(user: @player, button_position: 1, name: "Wall", units_position: army(73..91))
    render partial: "setups/panel", locals: { board: "cyvasse-match", slots: Setup.slots_for(@player) }

    assert_select "[data-controller=cyvasse-setups][data-cyvasse-setups-url-value=?]", setups_path
    assert_select "[data-action=?]", "cyvasse-setups:load->cyvasse-match#loadLineup cyvasse-setups:collect->cyvasse-match#collectLineup"
    assert_select "li[data-cyvasse-setups-target=slot]", 3
    assert_select "li[data-slot='1'] button[data-slot-load][data-lineup=?]:not([disabled])", army(73..91), "Wall"
    assert_select "li[data-slot='2'] button[data-slot-load][disabled]", "Empty slot 2"
    assert_select "li button[data-action='cyvasse-setups#save']", 3
    assert_select "input[data-cyvasse-setups-target=name][maxlength='20']"
  end

  test "a legacy lineup with no name, or that is not a whole army, or with markup in its name" do
    rows = [ [ 1, "", army(52..70) ], [ 2, "Broken", army(52..69) ], [ 3, "<b>x</b>", army(52..70) ] ]
    Setup.insert_all!(rows.map do |slot, name, units|
      { user_id: @player.id, button_position: slot, name: name, units_position: units, created_at: Time.current, updated_at: Time.current }
    end)
    render partial: "setups/panel", locals: { board: "cyvasse-game", slots: Setup.slots_for(@player) }

    assert_select "li[data-slot='1'] button[data-slot-load]:not([disabled])", "Lineup 1"
    assert_select "li[data-slot='2'] button[data-slot-load][disabled]", "Broken"
    assert_select "li[data-slot='3'] button b", 0, "a name is escaped"
    assert_includes rendered, "&lt;b&gt;x&lt;/b&gt;"
  end

  test "a visitor is offered sign-in instead of slots" do
    render partial: "setups/panel", locals: { board: "cyvasse-game", slots: nil }
    assert_select "[data-controller=cyvasse-setups]", 0
    assert_select "a[href=?]", signin_path, "Sign in"
  end

  private

  def army(hexes) = hexes.to_a.each_with_index.map { |hex, i| "#{i + 1}:#{hex}|" }.join
end
