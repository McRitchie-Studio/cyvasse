require "test_helper"

# [integration] The onboarding after a sign-in (OnboardingController,
# OnboardingPrompt): it opens once for an incomplete account, saves each step,
# can be skipped a step at a time or left for later, resumes on the next
# sign-in, and never opens for a complete account.
class OnboardingFlowTest < ActionDispatch::IntegrationTest
  include LiveResults

  setup do
    @rook = User.create!(email: "rook@example.com", name: "Temp", legacy_id: 11)
    @rook.update_columns(name: nil, slug: "user-#{@rook.id}", username: "the rook!")
    rival = player("rival")
    Match.create!(home_user: @rook, away_user: rival, winner: @rook, legacy_id: 900, match_status: Match::FINISHED,
                  finish_reason: "king", created_at: Time.zone.parse("2016-03-04"))
  end

  test "walks an imported player through every step and back to the page they wanted" do
    log_in_as(@rook)
    get leaderboard_path
    assert_redirected_to onboarding_path

    follow_redirect!
    assert_select "[data-onboarding-progress]", "Step 1 of 4"
    assert_select "[data-stat=played]", "1"
    assert_select "[data-stat=wins]", "1"
    assert_select "[data-stat=first-game]", /March 04, 2016/
    patch onboarding_step_path("welcome")
    assert_redirected_to onboarding_path(step: "username")

    follow_redirect!
    assert_select "[data-legacy-username]", /the rook!/
    assert_select "input[name=username][value=the_rook]"
    patch onboarding_step_path("username"), params: { username: "the_rook" }
    assert_redirected_to onboarding_path(step: "profile")

    patch onboarding_step_path("profile"), params: { name: "Rook Ravenholt", skin: "pencil", birth_year: "1990", birth_month: "7", birth_day: "14" }
    assert_redirected_to onboarding_path(step: "contact")

    freeze_time do
      patch onboarding_step_path("contact"), params: { email_updates: "1" }
      assert_redirected_to leaderboard_path
      assert_equal "You're all set.", flash[:notice]
      @rook.reload
      assert_equal [ "the_rook", "Rook Ravenholt", "pencil", 1990, 7, 14, true, Time.current ],
                   [ @rook.username, @rook.name, @rook.piece_skin, @rook.birth_year, @rook.birth_month, @rook.birth_day,
                     @rook.email_updates, @rook.email_updates_at ]
    end
    assert_empty @rook.onboarding_missing
  end

  test "keep me posted can be turned off, and the answer is still recorded" do
    log_in_as(@rook)
    patch onboarding_step_path("contact"), params: { email_updates: "0" }
    assert_equal false, @rook.reload.email_updates
    assert_not_nil @rook.email_updates_at
  end

  test "optional steps can be skipped; the username cannot while it is unplayable" do
    log_in_as(@rook)
    post skip_onboarding_step_path("username")
    assert_redirected_to onboarding_path(step: "username")
    assert_nil @rook.reload.onboarding_status("username")

    post skip_onboarding_step_path("profile")
    assert_redirected_to onboarding_path(step: "contact")
    post skip_onboarding_step_path("contact")
    assert_equal %w[skipped skipped], [ @rook.reload.onboarding_status("profile"), @rook.onboarding_status("contact") ]
    assert_nil @rook.email_updates, "a skip records no consent"
  end

  test "skip for now leaves, and the next sign-in resumes where the player stopped" do
    log_in_as(@rook)
    get root_path
    follow_redirect!
    patch onboarding_step_path("welcome")
    get onboarding_path(step: "username")
    assert_select "a[data-test=onboarding-leave][href='/']"
    get root_path
    assert_response :success, "the flow opens once per sign-in"

    get logout_path
    log_in_as(@rook)
    get root_path
    follow_redirect!
    assert_select "[data-onboarding-step=username]"
  end

  test "a bad username is refused with the rule" do
    player("taken")
    log_in_as(@rook)
    patch onboarding_step_path("username"), params: { username: "Taken" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /taken/
    patch onboarding_step_path("username"), params: { username: "no" }
    assert_select "[role=alert]", /3 to 20/
  end

  test "a name another player holds, and an impossible birthday, are refused" do
    player("rook_ravenholt", name: "Rook Ravenholt")
    log_in_as(@rook)
    patch onboarding_step_path("profile"), params: { name: "Rook Ravenholt" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /taken/
    patch onboarding_step_path("profile"), params: { name: "Rook R", birth_year: "1990", birth_month: "2", birth_day: "31" }
    assert_select "[role=alert]", /not a real date/
    assert_nil @rook.reload.name
  end

  test "a complete account signs in straight to its page" do
    arya = player("arya")
    log_in_as(arya)
    get leaderboard_path
    assert_response :success
  end

  test "an unknown step is a 404, and a guest is sent home" do
    log_in_as(@rook)
    patch onboarding_step_path("password")
    assert_response :not_found

    reset!
    post live_seeks_path
    get onboarding_path
    assert_redirected_to root_path
  end

  test "signed out, the page asks for a sign-in" do
    get onboarding_path
    assert_redirected_to login_path
  end
end
