require "test_helper"

# [integration] Changing the username from the profile (task
# cyvasse-profile-username-edit): the engine's /profile and /profile/edit carry
# the Username rows (config/initializers/studio.rb), the card saves through
# UsernamesController with the model's rules, a refusal comes back to the card,
# changes are rate-limited, and a guest or an email-handoff session may change
# it too.
class ProfileUsernameTest < ActionDispatch::IntegrationTest
  include HubAssertions
  include LiveResults

  setup do
    UsernamesController::RATE_STORE.clear
    @arya = player("arya")
  end

  def change_username(name)
    patch username_path, params: { username: name, from: "profile", return_to: edit_profile_path }
  end

  test "the profile pages lead with the username" do
    log_in_as(@arya)

    get profile_path
    assert_equal "username", css_select("[data-profile-section]").first["data-profile-section"]
    assert_select "[data-profile-section=username] [data-username]", "arya"

    get edit_profile_path
    sections = css_select("[data-profile-section]").map { |section| section["data-profile-section"] }
    assert_equal %w[username name], sections.first(2), "the Username card sits above Name"
    assert_select "#studio-profile-form input#profile_username[form=profile-username-form][value=arya]"
    assert_select "#studio-profile-form form", 0
    assert_select "form#profile-username-form[action='/username']", 1
    assert_select "#studio-profile-form form#profile-username-form", 0, "the card's form is outside the engine's"
  end

  test "a new username saves, and the navbar and the leaderboard read it" do
    live_result(@arya, player("bran"), winner: @arya)
    log_in_as(@arya)

    change_username("  No_One  ")
    assert_redirected_to edit_profile_path
    assert_equal "You play as No_One.", flash[:notice]
    assert_equal "No_One", @arya.reload.username

    follow_redirect!
    assert_select "input#profile_username[value=No_One]"
    assert_match "No_One", css_select("header").text, "the navbar shows the new name"

    get leaderboard_path
    assert_select "[data-leaderboard-row=No_One] .leaderboard-name", "No_One"
    assert_select "[data-leaderboard-row=arya]", 0
  end

  test "a taken, badly formed or reserved name comes back to the card with why" do
    player("jon")
    log_in_as(@arya)

    {
      "JON" => "Username is taken.",
      "no spaces" => "Username is 3 to 20 letters, digits or underscores.",
      "Admin" => "Username is reserved."
    }.each do |name, reason|
      change_username(name)
      assert_redirected_to edit_profile_path(anchor: "username")
      follow_redirect!
      assert_select "#profile_username_error", reason
      assert_select "input#profile_username[value='#{name}']"
    end
    assert_equal "arya", @arya.reload.username
  end

  test "changes are rate-limited, failed attempts included" do
    log_in_as(@arya)
    UsernamesController::RATE.times { |n| change_username(n.even? ? "admin" : "arya_#{n}") }
    assert_equal "arya_9", @arya.reload.username

    change_username("faceless")
    assert_redirected_to edit_profile_path(anchor: "username")
    follow_redirect!
    assert_select "#profile_username_error", UsernamesController::TOO_OFTEN
    assert_equal "arya_9", @arya.reload.username

    patch username_path, params: { username: "faceless" }
    assert_redirected_to username_path(return_to: matches_path)
    assert_equal UsernamesController::TOO_OFTEN, flash[:alert]
    assert_equal "arya_9", @arya.reload.username
  end

  test "the limit is per player" do
    log_in_as(@arya)
    UsernamesController::RATE.times { change_username("admin") }
    delete logout_path

    sansa = player("sansa")
    log_in_as(sansa)
    change_username("lady_sansa")
    assert_equal "lady_sansa", sansa.reload.username
  end

  test "a guest can trade its Guest_ name for a real one" do
    get play_path
    post live_seeks_path
    guest = User.where(guest: true).last
    assert_match User::GUEST_USERNAME, guest.username

    change_username("hot_pie")
    assert_equal "hot_pie", guest.reload.username
  end

  test "an email-handoff session may change the username: it is not a sign-in method" do
    previous = ENV[EmailHandoff::KEY_ENV]
    ENV[EmailHandoff::KEY_ENV] = hub_public_pem
    EmailHandoffsController::RATE_STORE.clear
    get email_handoff_path, params: { assertion: hub_assertion(@arya.email) }

    change_username("cat_of_canals")
    assert_redirected_to edit_profile_path
    assert_equal "cat_of_canals", @arya.reload.username
  ensure
    ENV[EmailHandoff::KEY_ENV] = previous
  end
end
