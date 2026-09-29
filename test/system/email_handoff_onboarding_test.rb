require "application_system_test_case"

# [e2e] A returning legacy player clicks the hub's email CTA: the handoff
# signs them in, the welcome back shows their old record, they keep a
# username, leave the rest for later and play, at desktop width and on a
# 375px phone with no sideways scroll. SCREENSHOTS=1 saves each step to
# tmp/screenshots/onboarding-<width>-<step>.png.
class EmailHandoffOnboardingTest < ApplicationSystemTestCase
  include HubAssertions

  setup do
    @previous_key = ENV[EmailHandoff::KEY_ENV]
    ENV[EmailHandoff::KEY_ENV] = hub_public_pem
    # The signed_in beacon is an image on the hub; the page's load waits for
    # it, so point it at a port that refuses at once.
    @previous_hub = ENV["EMAIL_ANALYTICS_URL"]
    ENV["EMAIL_ANALYTICS_URL"] = "http://127.0.0.1:9"
    @rook = User.create!(email: "rook@example.com", name: "Temp", legacy_id: 11)
    @rook.update_columns(name: nil, slug: "user-#{@rook.id}", username: "the rook!")
    rival = User.create!(email: "rival@example.com", name: "Rival", username: "rival")
    3.times do |i|
      Match.create!(home_user: @rook, away_user: rival, winner: i.zero? ? rival : @rook, legacy_id: 900 + i,
                    match_status: Match::FINISHED, finish_reason: "king", created_at: Time.zone.parse("2015-02-01") + i.days)
    end
    Setup.new(user: @rook, button_position: 1, units_position: "1:60|", name: "Old").save!(validate: false)
  end

  teardown do
    ENV[EmailHandoff::KEY_ENV] = @previous_key
    ENV["EMAIL_ANALYTICS_URL"] = @previous_hub
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  [ nil, 375 ].each do |width|
    label = width ? "#{width}px" : "desktop"

    test "email CTA to welcome back to username to play, #{label}" do
      phone!(width) if width
      visit email_handoff_path(assertion: hub_assertion(@rook.email, ref: "hub-delivery-token-0101"))

      assert_selector "[data-onboarding-step=welcome]"
      assert_no_current_path(/assertion/)
      assert_text "Welcome back, the rook!"
      within("[data-legacy-stats]") do
        assert_selector "[data-stat=played]", text: "3"
        assert_selector "[data-stat=wins]", text: "2"
        assert_selector "[data-stat=first-game]", text: "February 1, 2015"
        assert_selector "[data-stat=lineups]", text: "1"
      end
      step_shot(width, "1-welcome")
      click_on "Continue"

      assert_selector "[data-onboarding-step=username]"
      assert_field "Username", with: "the_rook"
      step_shot(width, "2-username")
      click_on "Save username"

      assert_selector "[data-onboarding-step=profile]"
      step_shot(width, "3-profile")
      click_on "Skip this step"

      assert_selector "[data-onboarding-step=contact]"
      step_shot(width, "4-contact")
      click_on "Skip for now"

      assert_current_path root_path
      click_on "Play Now", match: :first
      assert_current_path %r{\A/live/\d+\z}
      assert_equal "the_rook", @rook.reload.username
      step_shot(width, "5-play")
    end
  end

  private

  def phone!(width)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height: 844, deviceScaleFactor: 1, mobile: true)
  end

  # On a phone, every step fits: no sideways scroll.
  def step_shot(width, name)
    if width
      scroll, client = page_widths
      assert_equal width, client
      assert_operator scroll, :<=, client, "#{name}: no sideways scroll at #{width}px"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/onboarding-#{width || "desktop"}-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
