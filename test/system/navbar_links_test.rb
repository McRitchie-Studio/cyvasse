require "application_system_test_case"

# [e2e] The navbar's My games and Leaderboard links in a real browser: the
# desktop bar carries both, the Leaderboard with the player's rank, and a
# click lands on the page and marks it current; at 390px the phone row shows
# them with no sideways page scroll. SCREENSHOTS=1 saves each to
# tmp/screenshots/nav-links-*.png.
class NavbarLinksTest < ApplicationSystemTestCase
  include LiveResults

  setup do
    arya = player("arya")
    @brienne = player("brienne")
    live_result(arya, @brienne, winner: arya)
    visit link_path(token: Studio::Link.create_magic_link(email: @brienne.email).token)
    assert_text "Signed in as Brienne"
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "desktop: My games and Leaderboard with the rank, and the current page marked" do
    visit root_path
    within("nav[aria-label=Main]", match: :first) do
      assert_link "My games", href: "/matches"
      assert_link href: "/leaderboard", text: /Leaderboard\s*#2/
      click_link href: "/leaderboard"
    end
    assert_current_path leaderboard_path
    assert_selector "nav[aria-label=Main] a[href='/leaderboard'][aria-current=page]", visible: true
    screenshot("desktop")
  end

  test "390px: the phone row shows both links with no sideways scroll" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit leaderboard_path
    row = find("nav[aria-label=Main]", visible: true)
    assert_equal "My games Leaderboard #2", row.text.squish
    assert_selector "nav[aria-label=Main]", visible: true, count: 1

    scroll, client = page_widths
    assert_equal 390, client
    assert_operator scroll, :<=, client, "no sideways scroll at 390px"
    screenshot("390")
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/nav-links-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
