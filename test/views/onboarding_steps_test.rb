require "test_helper"

# [component] Each onboarding step rendered alone (app/views/onboarding): the
# legacy stats, the username suggestion, the name, skin and birthday form, and
# the sign-in and email-preference step in its three sign-in states.
class OnboardingStepsTest < ActionView::TestCase
  setup do
    @user = User.new(id: 7, email: "rook@example.com", username: "the rook!", legacy_id: 11)
  end

  def as(user, handoff: false)
    view.define_singleton_method(:current_user) { user }
    view.define_singleton_method(:current_skin) { :vector }
    view.define_singleton_method(:email_handoff_session?) { handoff }
  end

  test "welcome back shows what came across" do
    as(@user)
    @stats = { played: 1234, wins: 700, first_game_on: Date.new(2015, 2, 1), lineups: 3 }
    render partial: "onboarding/welcome"

    assert_select "h1", "Welcome back, the rook!"
    assert_select "[data-stat=played]", "1,234"
    assert_select "[data-stat=wins]", "700"
    assert_select "[data-stat=first-game]", "February 1, 2015"
    assert_select "[data-stat=lineups]", "3"
    assert_select "form[action='/onboarding/welcome'] input[name=_method][value=patch]"
  end

  test "welcome back with no games says so" do
    as(@user)
    @stats = { played: 0, wins: 0, first_game_on: nil, lineups: 0 }
    render partial: "onboarding/welcome"
    assert_select "[data-stat=first-game]", "None yet"
  end

  test "an unplayable legacy name comes with a suggestion" do
    as(@user)
    @suggestion = "the_rook"
    render partial: "onboarding/username"

    assert_select "h1", "Pick a username"
    assert_select "[data-legacy-username]", /the rook!/
    assert_select "input[name=username][value=the_rook][maxlength='20'][required]"
    assert_select "input[type=submit][value='Save username']"
  end

  test "a playable name is offered to keep" do
    @user.username = "the_rook"
    as(@user)
    @suggestion = "the_rook"
    render partial: "onboarding/username"

    assert_select "h1", "Keep your username?"
    assert_select "[data-legacy-username]", 0
    assert_select "input[type=submit][value='Keep it']"
  end

  test "the profile step asks for a name, a skin and an optional birthday, and can be skipped" do
    as(@user)
    render partial: "onboarding/profile"

    assert_select "input[name=name][required]"
    assert_select "input[type=radio][name=skin]", Piece::SKINS.size
    assert_select "input[type=radio][name=skin][value=vector][checked]"
    assert_select "select[name=birth_year] option[value='#{Date.current.year - 5}']"
    assert_select "legend", /optional/
    assert_select "form[action='/onboarding/profile/skip'] button", "Skip this step"
  end

  test "keep me posted is on by default" do
    as(@user)
    render partial: "onboarding/contact"

    assert_select "input[type=checkbox][name=email_updates][value='1'][checked]"
    assert_select "input[type=hidden][name=email_updates][value='0']"
    assert_select "form[action='/onboarding/contact/skip']"
  end

  test "keep me posted shows a saved no" do
    @user.email_updates = false
    as(@user)
    render partial: "onboarding/contact"
    assert_select "input[type=checkbox][name=email_updates][checked]", 0
  end

  test "Google can be added from an ordinary session" do
    skip "this app offers no Google sign-in" unless Studio.auth_method?(:google)
    as(@user)
    render partial: "onboarding/contact"
    assert_select "[data-sign-in-google] form[action^='/auth/google_oauth2'] button", /Add Google/
  end

  test "a handoff session confirms by email before adding Google" do
    skip "this app offers no Google sign-in" unless Studio.auth_method?(:google)
    as(@user, handoff: true)
    render partial: "onboarding/contact"
    assert_select "[data-sign-in-google] form[action='/account/confirmation'] button", "Email me a confirmation link"
    assert_select "[data-sign-in-google] form[action^='/auth/google_oauth2']", 0
  end

  test "Google already linked says so" do
    skip "this app offers no Google sign-in" unless Studio.auth_method?(:google)
    @user.provider = "google_oauth2"
    as(@user)
    render partial: "onboarding/contact"
    assert_select "[data-sign-in-google]", /Google sign-in is on/
    assert_select "[data-sign-in-google] form", 0
  end
end
