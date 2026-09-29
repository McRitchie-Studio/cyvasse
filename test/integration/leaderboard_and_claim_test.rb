require "test_helper"

# [integration] The leaderboards over real requests, and a guest's games
# claimed through the real magic-link sign-in: in the same browser (the
# session remembers the guest) and in another one (the signed claim token in
# the email link's return address).
class LeaderboardAndClaimTest < ActionDispatch::IntegrationTest
  include LiveResults

  setup do
    @qavo = computer
  end

  # Play Now as a signed-out visitor: the session is a guest's now.
  def become_guest(session = self)
    session.post live_seeks_path
    LiveSeek.last.user
  end

  def consume_link(session = self, email:, return_to: nil)
    token = Studio::Link.create_magic_link(email:, return_to:).token
    session.post link_consume_path(token:)
  end

  test "the landing page shows an empty live leaderboard with a Play Now call" do
    get root_path
    assert_select "[data-leaderboard-card]" do
      assert_select "h2", "Live leaderboard"
      assert_select "form[action='#{live_seeks_path}'] button[data-leaderboard-empty]", /Be the first on the board — Play Now/
    end
  end

  test "the landing card lists the top ten by live wins, never a computer or a guest" do
    guest = User.create_guest!(rng: Random.new(2))
    live_result(guest, @qavo, winner: guest)
    players = (1..11).map { |i| player("champ#{i.to_s.rjust(2, '0')}") }
    players.each_with_index { |p, i| (i + 1).times { live_result(p, @qavo, winner: p) } }

    get root_path
    names = css_select("[data-leaderboard-card] [data-leaderboard-row]").map { _1["data-leaderboard-row"] }
    assert_equal players.reverse.first(10).map(&:username), names
    assert_no_match(/Guest_|#{@qavo.username}/, css_select("[data-leaderboard-card]").text)
  end

  test "the leaderboard page shows the live board and the all-time one" do
    arya = player("arya", wins: 12, losses: 3)
    brienne = player("brienne")
    live_result(brienne, @qavo, winner: brienne)

    get leaderboard_path
    assert_response :success
    assert_select "[data-board=live] [data-leaderboard-row]", 1
    assert_select "[data-board=live] [data-leaderboard-row=brienne]", /1\s*W.*0\s*L/m

    get leaderboard_path(board: "all-time")
    assert_select "[data-board=all-time] [data-leaderboard-row=arya]", /12\s*W.*3\s*L/m
    assert_equal "arya", arya.username
  end

  test "a guest's join page sends a sign-in link that comes back with a claim token" do
    guest = become_guest
    get join_leaderboard_path(result: "win")
    assert_select "h1", "Put your win on the leaderboard"
    return_to = css_select("input[name=return_to]").first["value"]
    assert_match %r{\A/leaderboard\?claim=}, return_to

    post magic_link_request_path, params: { email: "arya@example.com", return_to: }
    assert_equal return_to, Studio::Link.last.return_to
    token = Rack::Utils.parse_query(URI(return_to).query)["claim"]
    assert_equal guest, GuestClaim.guest_from_token(token)
  end

  test "signing in from the guest's browser claims the guest's live win" do
    guest = become_guest
    match = live_result(guest, @qavo, winner: guest)
    arya = player("arya")

    consume_link(email: arya.email, return_to: leaderboard_path)
    assert_redirected_to leaderboard_path

    assert_equal [ arya, arya ], [ match.reload.home_user, match.winner ]
    assert_nil User.find_by(id: guest.id)
    follow_redirect!
    assert_select "[data-leaderboard-row=arya]"
  end

  test "a guest who signed out is still claimed at the next sign-in" do
    guest = become_guest
    match = live_result(guest, @qavo, winner: guest)
    delete logout_path
    arya = player("arya")

    consume_link(email: arya.email)
    assert_equal arya, match.reload.winner
  end

  test "a brand-new account claims the win, then picks a username for the board" do
    guest = become_guest
    match = live_result(guest, @qavo, winner: guest)

    consume_link(email: "newcomer@example.com", return_to: leaderboard_path(claim: GuestClaim.token_for(guest)))
    newcomer = User.find_by!(email: "newcomer@example.com")
    assert_equal newcomer, match.reload.winner

    follow_redirect!
    assert_redirected_to username_path(return_to: leaderboard_path)
    patch username_path, params: { username: "newcomer", return_to: leaderboard_path }
    follow_redirect!
    assert_select "[data-leaderboard-row=newcomer]"
  end

  test "opening the email link in another browser claims through the token" do
    guest_browser = open_session
    guest = become_guest(guest_browser)
    match = live_result(guest, @qavo, winner: guest)
    arya = player("arya")
    return_to = leaderboard_path(claim: GuestClaim.token_for(guest))

    phone = open_session
    consume_link(phone, email: arya.email, return_to:)
    assert_equal guest, match.reload.winner, "the phone's session never saw the guest"
    phone.follow_redirect!
    assert_equal arya, match.reload.winner
    assert_nil User.find_by(id: guest.id)
  end

  test "a forged claim token claims nothing" do
    guest = become_guest(open_session)
    match = live_result(guest, @qavo, winner: guest)
    arya = player("arya")

    consume_link(email: arya.email)
    get leaderboard_path(claim: "#{GuestClaim.token_for(guest)}x")
    assert_response :success
    assert_equal guest, match.reload.winner
  end

  test "a claim link opened by a player who did not just sign in claims nothing" do
    guest = become_guest(open_session)
    match = live_result(guest, @qavo, winner: guest)
    consume_link(email: player("arya").email)
    travel 3.minutes
    get leaderboard_path(claim: GuestClaim.token_for(guest))
    assert_equal guest, match.reload.winner
  end

  test "a signed-in account signing in again claims nothing" do
    arya = player("arya")
    brienne = player("brienne")
    match = live_result(brienne, @qavo, winner: brienne)
    consume_link(email: brienne.email)
    consume_link(email: arya.email)

    assert_equal brienne, match.reload.winner
  end

  test "a guest's match page names the way back, with a claim token for this guest only" do
    guest = become_guest
    match = live_result(guest, @qavo, winner: guest)

    get match_path(match)
    return_to = css_select("[data-controller=cyvasse-match]").first["data-cyvasse-match-return-to-value"]
    assert_match %r{\A/matches/#{match.id}\?claim=}, return_to
    assert_equal guest, GuestClaim.guest_from_token(Rack::Utils.parse_query(URI(return_to).query)["claim"])
    assert_select "[data-cyvasse-match-target=claimWin]", 0, "the old card is gone: the modal asks"

    arya = player("arya")
    consume_link(email: arya.email)
    get match_path(match)
    assert_nil css_select("[data-controller=cyvasse-match]").first["data-cyvasse-match-return-to-value"]
  end
end
