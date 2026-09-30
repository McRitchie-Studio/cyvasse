require "application_system_test_case"

# [e2e] A player changes their username from the profile in a real browser
# (task cyvasse-profile-username-edit), at desktop width and on a 390px phone:
# the card above Name saves on its own, a refusal shows in the card, the
# navbar shows the new name at once, and the leaderboard row follows.
# SCREENSHOTS=<dir> saves each step there.
class ProfileUsernameSystemTest < ApplicationSystemTestCase
  include LiveResults

  setup do
    UsernamesController::RATE_STORE.clear
    @arya = player("arya")
    live_result(@arya, player("bran"), winner: @arya)
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  { "desktop" => nil, "390px" => [ 390, 844 ] }.each do |label, phone|
    test "#{label}: a player edits the username on the profile and the navbar and leaderboard follow" do
      phone!(*phone) if phone
      sign_in(@arya)
      visit edit_profile_path

      cards = all("[data-profile-section]").map { |card| card["data-profile-section"] }
      assert_equal %w[username name], cards.first(2), "the Username card sits above Name"
      assert_no_sideways_scroll if phone

      within("[data-profile-section=username]") do
        fill_in "Username", with: "bran"
        click_button "Save"
      end
      within("[data-profile-section=username]") { assert_selector "[role=alert]", text: "Username is taken." }
      screenshot("#{label}-taken")

      fill_in "First name", with: "Arya"
      within("[data-profile-section=username]") do
        fill_in "Username", with: "No_One"
        click_button "Save"
      end
      assert_text "You play as No_One."
      within("header") { assert_text "No_One" } unless phone
      assert_equal "No_One", @arya.reload.username
      assert_equal "Arya", @arya.name, "the card saves the username alone, never the engine's form"
      screenshot("#{label}-saved")

      visit profile_path
      within("[data-profile-section=username]") { assert_selector "[data-username]", text: "No_One" }

      visit leaderboard_path
      assert_selector "[data-leaderboard-row=No_One] .leaderboard-name", text: "No_One"
      assert_no_selector "[data-leaderboard-row=arya]"
    end
  end

  private

  def sign_in(user)
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.player_name}"
  end

  def phone!(width, height)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: 1, mobile: true)
  end

  def assert_no_sideways_scroll
    scroll, client = page_widths
    assert_operator scroll, :<=, client, "no sideways scroll at phone width"
  end

  def screenshot(name)
    dir = ENV["SCREENSHOTS"]
    return unless dir

    sleep 0.4
    page.save_screenshot(File.join(dir, "profile-username-e2e-#{name}.png"))
  end
end
