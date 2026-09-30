require "application_system_test_case"

# [e2e] A Play Now guest's game ends in a real browser: the game-over modal
# (the engine's host) asks them to sign in or play again; signing in, by
# Google (OmniAuth's mock) or by the emailed link, brings them back to the
# match, which is now their account's. Closing the modal leaves the final
# board. SCREENSHOTS=1 saves each step to tmp/screenshots.
class GameOverSignInSystemTest < ApplicationSystemTestCase
  MODAL = "[data-test=game-over-modal]".freeze

  setup do
    Rails.configuration.x.live_search_time = 20.seconds
    Rails.configuration.x.live_splash_time = 0.5.seconds
    OmniAuth.config.test_mode = true
  end

  teardown do
    Rails.configuration.x.live_search_time = nil
    Rails.configuration.x.live_splash_time = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  # Play Now as a visitor, straight to a computer player, with the guest's
  # army in so the game is under way.
  def guest_in_a_game
    visit root_path
    click_on "Play Now"
    assert_text "Finding an opponent"
    click_on "Play the computer now"
    assert_selector "[data-controller=cyvasse-match]", wait: 8
    guest = LiveSeek.last.user
    match = Match.involving(guest).last
    match.set_up!(guest, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    [ guest, match.reload ]
  end

  test "a guest who resigns signs in with Google and comes back to the game, now theirs" do
    guest, match = guest_in_a_game
    # Resigned on the server: a click can beat Turbo's confirm on a slow runner.
    match.resign!(guest)
    visit match_path(match)

    within(MODAL) do
      assert_selector "h3", text: "You resigned."
      assert_selector "[data-test=game-over-points]", text: "+1 point on the leaderboard for finishing."
      assert_text "Sign in to keep your points and your record under your name"
      assert_button "Play another game"
    end
    screenshot("guest-modal")
    click_on "Sign in to keep your record"

    within("[data-test=auth-modal]") do
      assert_text "Keep your record"
      assert_field "Email"
    end
    screenshot("auth-modal")
    OmniAuth.config.mock_auth[:google_oauth2] =
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-1", info: { email: "newcomer@example.com", name: "New Comer" })
    click_on "Continue with Google"

    # A new account finishes itself first (the onboarding), username first.
    assert_selector "[data-onboarding-step=username] h1", text: "Pick a username"
    fill_in "Username", with: "newcomer"
    click_on "Save username"
    # Wait for the profile step: the username page has its own "Skip for now".
    assert_selector "[data-onboarding-step=profile]"
    click_on "Skip for now"

    assert_current_path(%r{\A/matches/#{match.id}(\?|\z)})
    newcomer = User.find_by!(email: "newcomer@example.com")
    assert_equal [ newcomer, match.away_user ], [ match.reload.home_user, match.winner ]
    assert_equal 1, newcomer.reload.losses, "the guest's record came along"
    assert_not User.exists?(guest.id)
    within(MODAL) do
      assert_selector "h3", text: "You resigned."
      assert_selector "[data-test=game-over-points]",
                      text: "+1 point on the leaderboard for finishing. You\u2019re now ##{Leaderboard.rank_for(newcomer).rank}."
      assert_no_text "Sign in"
      click_on "Close"
    end
    assert_no_selector MODAL
    assert_selector "[data-cyvasse-match-target=status]", text: "You resigned."
    assert_selector "svg.cyvasse-board g.hex.has-unit"
    screenshot("signed-in-board")
  end

  test "a guest who wins while watching signs in by email, and the win is the account's" do
    guest, match = guest_in_a_game
    visit match_path(match)
    assert_no_selector MODAL
    match.send(:finish!, winner: guest, reason: "king")

    within(MODAL, wait: 5) do
      assert_selector "h3", text: "You captured the king. You win."
      assert_selector "[data-test=game-over-points]", text: "+3 points on the leaderboard."
    end
    send_keys :escape
    assert_no_selector MODAL
    assert_selector "svg.cyvasse-board g.hex.has-unit", minimum: 1

    visit match_path(match)
    within(MODAL) { click_on "Sign in to keep your record" }
    within("[data-test=auth-modal]") do
      fill_in "Email", with: "arya@example.com"
      click_on "Email me a sign-in link"
    end
    within("[data-test=check-inbox-modal]") { assert_text "arya@example.com" }
    screenshot("check-inbox")

    visit link_path(token: Studio::Link.last.token)
    click_on "Sign in" if page.has_button?("Sign in", wait: 1)
    # A new account finishes itself first (the onboarding), username first.
    assert_selector "[data-onboarding-step=username] h1", text: "Pick a username"
    fill_in "Username", with: "arya"
    click_on "Save username"
    # Wait for the profile step: the username page has its own "Skip for now".
    assert_selector "[data-onboarding-step=profile]"
    click_on "Skip for now"

    assert_current_path(%r{\A/matches/#{match.id}})
    arya = User.find_by!(email: "arya@example.com")
    assert_equal arya, match.reload.winner
    assert_not User.exists?(guest.id)
    visit leaderboard_path
    assert_selector "[data-leaderboard-row=arya].is-you", text: /1\s*W/
  end

  test "a signed-in player gets Play another game, which starts a new search" do
    arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    match = Match.start_live!(arya, computer: true, rng: Random.new(4))
    match.set_up!(arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    match.reload.send(:finish!, winner: match.away_user, reason: "king")
    visit link_path(token: Studio::Link.create_magic_link(email: arya.email, return_to: match_path(match)).token)
    click_on "Sign in" if page.has_button?("Sign in", wait: 1)

    within(MODAL) do
      assert_selector "h3", text: "Your king fell. You were defeated."
      assert_no_text "Sign in"
      click_on "Play another game"
    end
    assert_text "Finding an opponent"
  end

  private

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    sleep 0.8 # past the modal's entrance
    page.save_screenshot(Rails.root.join("tmp/screenshots/game-over-#{name}.png"))
  end
end
