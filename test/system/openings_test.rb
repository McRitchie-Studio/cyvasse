require "application_system_test_case"

# [e2e] The opening picker and the value shading in a real browser: a visitor
# loads one of the twenty openings (app/javascript/cyvasse/openings.js) onto
# the board, and each unit's hex is shaded by what the piece is worth.
class OpeningsSystemTest < ApplicationSystemTestCase
  test "load an opening during setup against the computer; each hex is shaded by the worth of its piece" do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
    assert_selector ".cyvasse-dock .dock-unit", count: 19

    select "Crown Forward", from: "Opening"
    assert_text "near enough the middle to move first"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }

    assert_text "Loaded Crown Forward."
    assert_no_selector ".cyvasse-dock .dock-unit"
    # Crown Forward: the king on the second row's middle hex (66), the
    # trebuchet and catapult on the front row above it (56, 57). The shade
    # ranks mountain 0, then KILL_PRIORITY: trebuchet 7, catapult 8,
    # king 10.
    assert_selector "g.hex[data-hex='66'][data-unit-id='1-17'][data-rank='10'] .unit-shade[fill='url(#shade-1-10)']"
    assert_selector "g.hex[data-hex='56'][data-unit-id='1-14'][data-rank='7']"
    assert_selector "g.hex[data-hex='57'][data-unit-id='1-15'][data-rank='8']"
    assert_selector "g.hex[data-rank='0'] .unit-shade[fill='url(#shade-1-0)']", count: 2
    assert_selector "g.hex[data-rank]", count: 19
    screenshot("crown-forward")

    click_on "Start Game"
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    assert_selector "g.hex[data-rank]", count: 38
    assert_selector "g.hex[data-team='0'][data-rank='10'] .unit-shade[fill='url(#shade-0-10)']"
    screenshot("play")
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/openings-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
