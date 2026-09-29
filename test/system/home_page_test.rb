require "application_system_test_case"

# [e2e] The front door in a real browser: the action shot is painted under a
# black scrim, Rules leads to /rules, and a phone gets no sideways scroll.
# SCREENSHOTS=1 saves each view to tmp/screenshots.
class HomePageSystemTest < ApplicationSystemTestCase
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "the background is present, the text sits on a dark scrim, and Rules opens the rules" do
    visit root_path

    img = find("section.home-hero img[data-home-background]", visible: :all)
    assert page.evaluate_script("arguments[0].complete && arguments[0].naturalWidth > 0", img), "the action shot loaded"
    alpha = page.evaluate_script("getComputedStyle(document.querySelector('.home-hero-scrim')).backgroundColor")
    assert_match(/\Argba?\(0, 0, 0, 0\.[67]\d*\)\z/, alpha, "a black scrim of at least 60%")
    assert_equal "rgb(255, 255, 255)", page.evaluate_script("getComputedStyle(document.querySelector('.home-hero h1')).color")
    assert_selector ".home-hero [data-leaderboard-card]"
    assert_no_link "Play the computer"
    screenshot("desktop")

    click_on "Rules"
    assert_current_path rules_path
  end

  test "the front door fits a 390px phone" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit root_path
    assert_selector "section.home-hero a", text: "Play a friend"

    scroll, client = page.evaluate_script("[document.documentElement.scrollWidth, document.documentElement.clientWidth]")
    assert_equal 390, client
    assert_operator scroll, :<=, client, "no sideways scroll at 390px"
    screenshot("phone")
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/home-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
