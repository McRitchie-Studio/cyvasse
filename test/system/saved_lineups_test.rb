require "application_system_test_case"

# [e2e] Saved lineups in a real browser (piece 10b): a player loads a saved
# army during setup against the computer and in an online match, where the
# server locks in exactly that army, and saves the army on the board to a
# slot.
class SavedLineupsSystemTest < ApplicationSystemTestCase
  WALL = (73..91).each_with_index.map { |hex, i| "#{i + 1}:#{hex}|" }.join

  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne")
    Setup.create!(user: @arya, button_position: 1, name: "Back Wall", units_position: WALL)
  end

  test "load a saved lineup during setup against the computer, then save the army to another slot" do
    sign_in(@arya)
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
    assert_selector ".cyvasse-dock .dock-unit", count: 19

    click_on "Back Wall"
    assert_no_selector ".cyvasse-dock .dock-unit"
    (73..91).each_with_index do |hex, i|
      assert_selector "svg.cyvasse-board g.hex[data-hex='#{hex}'][data-unit-id='1-#{i + 1}']"
    end
    assert_text "Loaded Back Wall."
    assert_button "Start Game"
    screenshot("loaded")

    fill_in "Name to save as", with: "Copy"
    within("[data-slot='2']") { click_on "Save" }
    assert_text "Saved Copy to slot 2."
    within("[data-slot='2']") { assert_button "Copy" }
    assert_equal WALL, @arya.setups.find_by!(button_position: 2).units_position

    click_on "Start Game"
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
  end

  test "load a saved lineup in an online match; the server locks in that army" do
    match = Match.challenge!(@arya, "brienne")
    sign_in(@arya)
    visit match_path(match)
    assert_selector ".cyvasse-dock .dock-unit", count: 19

    click_on "Back Wall"
    assert_no_selector ".cyvasse-dock .dock-unit"
    click_on "Submit army"
    assert_selector "[role=status]", text: "Waiting for brienne to accept"
    assert_equal WALL, match.reload.home_units_position
  end

  private

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/lineups-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
