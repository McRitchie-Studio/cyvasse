require "application_system_test_case"

# [e2e] The opening picker and the marquee flair in a real browser: a visitor
# loads one of the twenty openings (app/javascript/cyvasse/openings.js) onto
# the board, and the king, dragon, elephants and trebuchet wear the gold halo.
class OpeningsSystemTest < ApplicationSystemTestCase
  test "load an opening during setup against the computer; the marquee pieces wear their flair" do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
    assert_selector ".cyvasse-dock .dock-unit", count: 19

    select "Crown Forward", from: "Opening"
    assert_text "near enough the middle to move first"
    within("[data-controller=cyvasse-openings]") { click_on "Load" }

    assert_text "Loaded Crown Forward."
    assert_no_selector ".cyvasse-dock .dock-unit"
    # Crown Forward: the king on the second row's middle hex (66), the
    # trebuchet and catapult on the front row above it (56, 57).
    assert_selector "g.hex[data-hex='66'][data-unit-id='1-17'].is-marquee"
    assert_selector "g.hex[data-hex='56'][data-unit-id='1-14'].is-marquee"
    assert_selector "g.hex[data-hex='57'][data-unit-id='1-15']"
    assert_no_selector "g.hex[data-hex='57'].is-marquee"
    assert_selector "g.hex.is-marquee", count: 5
    screenshot("crown-forward")

    click_on "Start Game"
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    assert_selector "g.hex.is-marquee", count: 10
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/openings-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
