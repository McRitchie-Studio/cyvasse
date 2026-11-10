require "application_system_test_case"

# [e2e] The play-times survey at phone width in dark mode (task
# cyvasse-play-times-survey): a legacy player from an email link skips the
# first-game question, picks times and days, finishes on "Play a game now", and
# an admin reads the result. SURVEY_SHOTS=<dir> saves play-times-q1-phone-dark.png,
# play-times-days-phone-dark.png and play-times-admin-results.png there.
class PlayTimesSurveySystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  REF = "PlayTimesRef0123456789"
  FINITE_ANIMATIONS = "document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).length"

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def shot(name)
    dir = ENV["SURVEY_SHOTS"].presence or return
    FileUtils.mkdir_p(dir)
    # Let a view transition finish, or the page it leaves bleeds into the shot
    # (a looping animation never finishes, so only finite ones count).
    Timeout.timeout(5) { sleep 0.05 until page.evaluate_script(FINITE_ANIMATIONS).zero? }
    page.save_screenshot(File.join(dir, name))
  end

  def step_key = find("[data-survey-step].is-active")["data-key"]

  # The step counter changes as a step starts to slide in, so a click on the
  # new step's option right then can land where the option is not yet, and the
  # survey never advances. Each step is asserted, then waited out until no
  # finite animation is running (the slide and the scroll to the top), before
  # the next click. Seen in the full suite (task cyvasse-adopts-glass-style).
  def assert_step(text)
    assert_text text
    Timeout.timeout(5) { sleep 0.05 until page.evaluate_script(FINITE_ANIMATIONS).zero? && page.evaluate_script("window.scrollY").zero? }
  end

  test "a legacy player skips question 1, picks times, and an admin reads it" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 760,
                                                                          deviceScaleFactor: 2, mobile: true)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    visit "/surveys/play-times?ref=#{REF}"
    assert_viewport_width 375
    assert_selector "[data-studio-survey].is-enhanced"
    assert_step "Question 1 of 6"
    assert_equal "first_game", step_key
    assert_text "Haven't played yet? Skip this one."
    find("[data-key=first_game] .studio-survey__tile", match: :first)
    shot("play-times-q1-phone-dark.png")

    click_on "Next" # not required: a player who has not played moves straight on
    assert_step "Question 2 of 6"
    assert_equal "times", step_key
    find("[data-key=times]").find("label", text: "🌆 Evening").click
    find("[data-key=times]").find("label", text: "🌙 Late night").click
    click_on "Next"
    assert_step "Question 3 of 6"
    assert_equal "days", step_key
    find("[data-key=days]").find("label", text: "Friday").click
    find("[data-key=days]").find("label", text: "Saturday").click
    shot("play-times-days-phone-dark.png")
    click_on "Next"
    assert_step "Question 4 of 6"
    find("[data-key=time_zone]").find("label", text: "Mountain").click
    assert_step "Question 5 of 6"
    find("[data-key=how_often]").find("label", text: "Every other week").click
    assert_step "Question 6 of 6"
    find("[data-key=anything_else] textarea").fill_in(with: "A reminder the day before")
    find("[data-survey-submit]").click

    assert_selector "h1, h2", text: "Thank you!"
    assert_link "Play a game now", href: "/play"
    overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    assert_operator overflow, :<=, 0, "the survey scrolls sideways at 375px"

    response = Studio::SurveyResponse.sole
    assert response.completed?
    assert_equal REF, response.email_ref
    assert_nil response.answers["first_game"]
    assert_equal %w[friday saturday], response.answers.dig("days", "value")

    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin", username: "boss")
    visit_magic_link(Studio::Link.create_magic_link(email: admin.email).token)
    assert_text "Signed in as #{admin.player_name}"
    visit "/admin/surveys"
    click_on "Cyvasse Night: tell us about you", match: :first
    assert_text "Which days work best?"
    assert_text "A reminder the day before"
    shot("play-times-admin-results.png")
  end
end
