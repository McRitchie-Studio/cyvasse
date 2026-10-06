require "application_system_test_case"

# [e2e] The first-game survey in Cyvasse's own layout at phone width (task
# cyvasse-first-game-survey; studio-engine docs/SURVEYS.md): a player from an
# email link taps through all six questions, lands on the thank-you screen with
# "Play another game", and the response is complete and credited to the email.
# Then an admin opens Surveys from the admin menu and reads the result.
# SURVEY_SHOTS=<dir> saves cyvasse-survey-phone-dark.png and
# cyvasse-admin-results.png there.
class FirstGameSurveySystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  REF = "AbCdEfGhIjKlMnOpQrSt12"

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def shot(name)
    dir = ENV["SURVEY_SHOTS"].presence or return
    FileUtils.mkdir_p(dir)
    page.save_screenshot(File.join(dir, name))
  end

  def step_key = find("[data-survey-step].is-active")["data-key"]

  test "a player answers the survey at phone width and an admin reads it" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 760,
                                                                          deviceScaleFactor: 2, mobile: true)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-color-scheme", value: "dark" } ])
    visit "/surveys/first-game?ref=#{REF}"
    assert_selector "[data-studio-survey].is-enhanced"
    # studio-engine 0.89 opens straight on question 1: no intro step, no Start
    # button, and no Back button. The title repeats question 1, so the engine
    # keeps it in the DOM but hides it visually.
    assert_selector "h1, h2", text: "How was your first game?", visible: :all
    assert_text "Question 1 of 6"
    assert_no_button "Start"
    assert_no_button "Back"
    find("[data-key=overall] .studio-survey__tile", match: :first) # the stepper is showing
    assert_equal "overall", step_key
    shot("cyvasse-survey-phone-dark.png")
    all("[data-key=overall] .studio-survey__tile")[3].click
    assert_text "Question 2 of 6"
    assert_button "Back" # Back appears from question 2 on
    find("[data-key=rules] input[value='5']", visible: :all).find(:xpath, "..").click
    assert_text "Question 3 of 6"
    find("[data-key=found_us]").find("label", text: "An email from us").click
    assert_text "Question 4 of 6"
    find("[data-key=liked]").find("label", text: "The board").click
    find("[data-key=liked]").find("label", text: "Playing the computer").click
    click_on "Next"
    assert_text "Question 5 of 6"
    find("[data-key=one_word] input").fill_in(with: "Tense")
    click_on "Next"
    assert_text "Question 6 of 6"
    find("[data-key=anything_else] textarea").fill_in(with: "More maps please")
    find("[data-survey-submit]").click

    assert_selector "h1, h2", text: "Thank you!"
    assert_text "We read every answer."
    assert_link "Play another game", href: "/play"
    overflow = page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth")
    assert_operator overflow, :<=, 0, "the survey scrolls sideways at 375px"

    response = Studio::SurveyResponse.sole
    assert response.completed?
    assert_equal REF, response.email_ref
    assert_equal %w[the_board playing_the_computer], response.answers.dig("liked", "value")

    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin", username: "boss")
    visit link_path(token: Studio::Link.create_magic_link(email: admin.email).token)
    assert_text "Signed in as #{admin.player_name}"
    find("button[aria-label='Toggle admin menu']", match: :first).click
    click_on "Surveys"
    assert_current_path "/admin/surveys"
    click_on "How was your first game?", match: :first
    assert_text "How clear were the rules?"
    assert_text "Tense"
    shot("cyvasse-admin-results.png")
  end
end
