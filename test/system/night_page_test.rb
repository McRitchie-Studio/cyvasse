require "application_system_test_case"

# [e2e] Cyvasse Night in a real browser (task cyvasse-night-event-page): the
# countdown ticks on the server's clock, the start shows in the visitor's own
# zone, Play Now is there while the night runs, and a 375px phone gets no
# sideways scroll in either theme. SCREENSHOTS=1 saves each view to
# tmp/screenshots/night-*.png.
class NightPageSystemTest < ApplicationSystemTestCase
  include ActiveSupport::Testing::TimeHelpers

  setup { @night = CyvasseNight.current }

  teardown do
    travel_back
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.clearTimezoneOverride") rescue nil # rubocop:disable Style/RescueModifier
  end

  test "before: the countdown ticks down and the start shows in the visitor's zone" do
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "America/New_York")
    travel_to(@night.starts_at - (1.day + 2.hours + 3.minutes + 30.seconds))
    visit night_path

    assert_selector "[data-controller=night-countdown][data-night-countdown-state=ticking]"
    assert_selector "[data-night-local]", text: /Your time: Tuesday, October 6.*9:00\sPM EDT/
    assert_selector "[data-unit=days]", text: "1"
    assert_selector "[data-unit=hours]", text: "02"
    assert_selector "[data-unit=minutes]", text: "03"
    first = find("[data-unit=seconds]").text.to_i
    assert_selector("[data-unit=seconds]", wait: 5) { |node| node.text.to_i < first }
    assert_selector "a[data-night-ics]"
    assert_selector "a[data-night-google]"
    screenshot("before-desktop")
  end

  test "a visitor in Mountain time is not told the time twice" do
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "America/Denver")
    travel_to(@night.starts_at - 1.day)
    visit night_path

    assert_selector "[data-night-countdown-state=ticking]"
    assert_no_selector "[data-night-local]"
  end

  test "during: Play Now leads and the countdown is to the end" do
    travel_to(@night.starts_at + 1.hour)
    visit night_path

    assert_selector "article[data-night-phase=during]"
    assert_selector ".night-countdown-label", text: /ends in/i
    assert_selector "[data-unit=hours]", text: "02"
    assert_button "Play Now"
    assert_selector "[data-night-leaderboard]"
    screenshot("during-desktop")
  end

  [ %w[before light], %w[during dark] ].each do |phase, theme|
    test "#{phase} fits a 375px phone in the #{theme} theme" do
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 2, mobile: true)
      travel_to(phase == "before" ? @night.starts_at - 3.days : @night.starts_at + 20.minutes)
      visit night_path
      page.execute_script("document.documentElement.classList.toggle('dark', #{theme == 'dark'})")

      assert_selector "article[data-night-phase=#{phase}]"
      assert_selector "[data-night-countdown-state=ticking]"
      scroll, client = page_widths
      assert_operator scroll, :<=, client, "no sideways scroll at 375px"
      screenshot("#{phase}-phone-#{theme}")
    end
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/night-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
