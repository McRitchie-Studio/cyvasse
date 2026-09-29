require "test_helper"

# [integration] Signing in from the game-over modal, over real requests: the
# Google path (OmniAuth's mock through the engine's callback) and the magic
# link both claim the guest this browser played as and bring the player back
# to the match; nothing in the request can name another guest; a failed claim
# is logged and the sign-in still stands.
class GameOverSignInTest < ActionDispatch::IntegrationTest
  include LiveResults

  setup do
    @qavo = computer
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def become_guest(session = self)
    session.post live_seeks_path
    LiveSeek.last.user
  end

  def google_as(email, uid: "g-#{email}", name: "Arya Stark")
    OmniAuth.config.mock_auth[:google_oauth2] =
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid:, info: { email:, name: })
  end

  def sign_in_with_google(return_to: nil)
    post return_to ? "/auth/google_oauth2?return_to=#{CGI.escape(return_to)}" : "/auth/google_oauth2"
    follow_redirect! # the mocked provider hands back to the callback
  end

  test "Google claims the guest's game and brings the player back to the match" do
    guest = become_guest
    match = live_result(guest, @qavo, winner: guest)
    google_as("newcomer@example.com")

    sign_in_with_google(return_to: match_path(match))
    newcomer = User.find_by!(email: "newcomer@example.com")
    assert_equal [ "google_oauth2", "g-newcomer@example.com" ], [ newcomer.provider, newcomer.uid ]
    assert_equal [ newcomer, newcomer ], [ match.reload.home_user, match.winner ]
    assert_nil User.find_by(id: guest.id)
    assert_redirected_to root_path

    follow_redirect!
    assert_redirected_to onboarding_path, "a new account finishes itself first"
    follow_redirect!
    patch onboarding_step_path("username"), params: { username: "newcomer" }
    get root_path
    assert_redirected_to match_path(match), "the home page sends them back once"
    follow_redirect!
    assert_response :success
    get root_path
    assert_response :success, "only once"
  end

  test "Google signs an existing account in and merges the guest's games into its own" do
    arya = player("arya", wins: 3)
    own = live_result(arya, @qavo, winner: arya)
    guest = become_guest
    guests = live_result(guest, @qavo, winner: guest)
    guest.update_columns(wins: 1)
    google_as(arya.email)

    sign_in_with_google(return_to: match_path(guests))
    assert_equal [ arya, arya ], [ own.reload.winner, guests.reload.winner ]
    assert_equal 4, arya.reload.wins
    follow_redirect!
    follow_redirect!
    assert_response :success
    assert_select "[data-controller=cyvasse-match]"
  end

  test "the magic link from the modal lands back on the match with the game claimed" do
    guest = become_guest
    match = live_result(guest, @qavo, winner: guest)
    arya = player("arya")
    get match_path(match)
    return_to = css_select("[data-controller=cyvasse-match]").first["data-cyvasse-match-return-to-value"]

    post magic_link_request_path, params: { email: arya.email, return_to: }, as: :json
    assert_equal({ "success" => true }, response.parsed_body)
    post link_consume_path(token: Studio::Link.last.token)
    assert_redirected_to return_to
    follow_redirect!
    assert_response :success
    assert_equal arya, match.reload.winner
  end

  test "nothing in the request can name another guest" do
    other = become_guest(open_session)
    theirs = live_result(other, @qavo, winner: other)
    mine = live_result(become_guest, @qavo, winner: @qavo)
    arya = player("arya")

    token = Studio::Link.create_magic_link(email: arya.email).token
    post link_consume_path(token:), params: { guest_user_id: other.id, guest_id: other.id, claim: other.id }
    get root_path(claim: other.id, guest_user_id: other.id)
    get match_path(mine, claim: other.to_param)

    assert_equal arya, mine.reload.home_user, "this browser's guest is claimed"
    assert_equal [ other, other ], [ theirs.reload.home_user, theirs.winner ], "the other is not"
    assert User.exists?(other.id)
  end

  test "Google's return address stays on this site" do
    become_guest
    google_as("newcomer@example.com")
    sign_in_with_google(return_to: "//evil.example/x")
    follow_redirect!
    assert_redirected_to onboarding_path
    get root_path
    assert_response :success
    assert_equal "/", path
  end

  test "a failed claim is logged and the sign-in still stands" do
    guest = become_guest
    match = live_result(guest, @qavo, winner: guest)
    google_as("newcomer@example.com")
    call = GuestClaim.method(:call)
    GuestClaim.define_singleton_method(:call) { |**| raise ActiveRecord::StatementInvalid, "boom" }
    begin
      assert_difference -> { ErrorLog.count }, 1 do
        sign_in_with_google(return_to: match_path(match))
      end
    ensure
      GuestClaim.define_singleton_method(:call, call)
    end
    newcomer = User.find_by!(email: "newcomer@example.com")
    assert_equal newcomer.id, session[Studio.session_key]
    assert_equal guest, match.reload.winner
    assert_equal guest.id, session[:guest_user_id], "the next sign-in tries again"
  end
end
