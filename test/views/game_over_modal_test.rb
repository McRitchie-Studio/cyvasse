require "test_helper"

# [component] The game-over and sign-in modals (modals/_game_over, modals/_auth,
# modals/_check_inbox), rendered alone: the points line or the computer-seat
# note; a guest is asked to sign in to keep their points and record and may
# play again; a signed-in player may play again or close;
# the sign-in card offers Google only where the app has it, then the magic link.
class GameOverModalTest < ActionView::TestCase
  test "a guest is asked to sign in, and may play again" do
    render partial: "modals/game_over", locals: { guest: true }

    assert_select "[data-test=game-over-modal]", 1
    assert_select "[data-test=game-over-result][x-text='props.result']"
    sign_in = assert_select("a[data-test=game-over-sign-in]", "Sign in to keep your record").first
    assert_match(/\$store\.modals\.swap\('auth', \{ returnTo: props\.returnTo/, sign_in["@click.prevent"])
    assert_equal join_leaderboard_path, sign_in["href"], "the no-script way in"
    assert_select "form[action=?][method=post] button[data-test=game-over-play-again]", live_seeks_path, "Play another game"
    assert_select "button[aria-label=Close]", 1
    assert_select "p[x-show='props.points > 0']", /Sign in to keep your points and your record under your name/
    assert_select "p[x-show='!(props.points > 0)']", /You played as a guest/
    assert_points_lines
  end

  test "a signed-in player may play again or close, and is not asked to sign in" do
    render partial: "modals/game_over", locals: { guest: false }

    assert_select "a[data-test=game-over-sign-in]", 0
    assert_no_match(/Sign in/, rendered)
    assert_select "form[action=?] button[data-test=game-over-play-again]", live_seeks_path, "Play another game"
    close = css_select("button").find { _1.text.strip == "Close" }
    assert_equal "$store.modals.close()", close["@click"]
    assert_points_lines
  end

  # The points line (+3 for a win, +1 for a loss or draw: cyvasse/game_over,
  # test/javascript/game_over_test.js) shows only when the game earned points;
  # a seat the computer held gets the honest note instead; a game that does
  # not count (points null) gets neither.
  def assert_points_lines
    assert_select "[data-test=game-over-points][x-show='props.points > 0'][x-text='props.pointsLine']", 1
    assert_select "[data-test=game-over-no-points][x-show='props.points === 0']", 1,
                  /The computer finished this game in your seat, so it scores no points/
    assert_no_match(/live leaderboard/, rendered)
  end

  test "the sign-in card offers Google, then the email link" do
    render partial: "modals/auth"

    assert_select "[data-test=auth-modal]", 1
    google = assert_select("form[action='/auth/google_oauth2'][method=post]:has(button[data-test=auth-google])").first
    assert_equal "googleAction", google[":action"], "the way back rides on the request"
    assert_match(/Continue with Google/, google.text)
    assert_select google, "input[name=authenticity_token]", 1
    assert_select "form[data-test=auth-email-form] input#auth-email[type=email]"
    assert_select "form[data-test=auth-email-form] button[type=submit]", /Email me a sign-in link/
    assert_includes rendered, "window.postMagicLink(this.email, this.props.returnTo)"
  end

  test "without Google the card is the email link alone" do
    methods = Studio.auth_methods
    Studio.auth_methods = %i[magic_link]
    render partial: "modals/auth"

    assert_select "[data-test=auth-google]", 0
    assert_select "form[data-test=auth-email-form]", 1
  ensure
    Studio.auth_methods = methods
  end

  test "the inbox card names the address it sent to" do
    render partial: "modals/check_inbox"
    assert_select "[data-test=check-inbox-modal] h3", "Check your inbox"
    assert_select "[x-text=email]"
  end
end
