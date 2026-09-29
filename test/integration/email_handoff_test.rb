require "test_helper"

# [integration] GET /auth/email_handoff over real requests: a good assertion
# signs a player in and opens the onboarding with the email's ref kept; every
# refusal leaves no session; a replay is refused; an unknown address lands on
# Play Now; the endpoint is rate limited, fails closed without its key, and
# never logs the assertion.
class EmailHandoffTest < ActionDispatch::IntegrationTest
  include HubAssertions
  include LiveResults

  setup do
    @previous_key = ENV[EmailHandoff::KEY_ENV]
    ENV[EmailHandoff::KEY_ENV] = hub_public_pem
    EmailHandoffsController::RATE_STORE.clear
    @legacy = User.create!(email: "old.timer@example.com", name: "Temp", legacy_id: 4242)
    @legacy.update_columns(name: nil, slug: "user-#{@legacy.id}", username: "old timer")
  end

  teardown { ENV[EmailHandoff::KEY_ENV] = @previous_key }

  def hand_off(assertion, **params)
    get email_handoff_path, params: { assertion:, **params }
  end

  def signed_in?
    get matches_path
    response.successful? || !response.location.to_s.end_with?(login_path)
  end

  test "a good assertion signs the player in and opens the onboarding, keeping the ref" do
    hand_off(hub_assertion(@legacy.email, ref: "hub-delivery-token-0042"), return_to: "/leaderboard")

    assert_redirected_to onboarding_path
    assert_not_includes response.location, "assertion"
    assert_equal "hub-delivery-token-0042", cookies[:email_ref]
    follow_redirect!
    assert_response :success
    assert_select "[data-onboarding-step=welcome]"
    assert_select "a[data-test=onboarding-leave][href='/leaderboard']"
    attempt = EmailHandoffAttempt.last
    assert_equal [ "signed_in", @legacy ], [ attempt.outcome, attempt.user ]
  end

  test "the first page after it draws the signed_in beacon for that ref" do
    player("arya", piece_skin: "vector", email_updates: true)
    hand_off(hub_assertion("arya@example.com", ref: "hub-delivery-token-0043"))
    assert_redirected_to root_path
    follow_redirect!
    assert_select "img[data-email-beacon][src$='/e/g/hub-delivery-token-0043?g=signed_in']"
  end

  test "a complete account goes to return_to, and only a local one" do
    arya = player("arya", piece_skin: "vector", email_updates: true)
    hand_off(hub_assertion(arya.email), return_to: "/leaderboard?board=all-time")
    assert_redirected_to "/leaderboard?board=all-time"

    [ "//evil.example/x", "https://evil.example", "/\\evil.example", "javascript:alert(1)" ].each do |target|
      reset!
      hand_off(hub_assertion(arya.email), return_to: target)
      assert_redirected_to root_path, "#{target} is not a local path"
    end
  end

  test "an open redirect is refused on the onboarding path too" do
    hand_off(hub_assertion(@legacy.email), return_to: "//evil.example")
    follow_redirect!
    assert_select "a[data-test=onboarding-leave][href='/']"
  end

  {
    "wrong issuer" => { iss: "evil.example" },
    "wrong audience" => { aud: "turf-monster" },
    "expired" => { iat: 10.minutes.ago.to_i, exp: 6.minutes.ago.to_i },
    "too long a lifetime" => { iat: 10.seconds.ago.to_i, exp: 591.seconds.from_now.to_i }
  }.each do |label, claims|
    test "#{label}: no session" do
      hand_off(hub_assertion(@legacy.email, **claims))
      assert_redirected_to root_path
      assert_not signed_in?
      assert_equal "rejected", EmailHandoffAttempt.last.outcome
    end
  end

  test "a bad signature: no session" do
    hand_off(hub_assertion(@legacy.email, key: OTHER_KEY))
    assert_not signed_in?
    assert_equal "bad_signature", EmailHandoffAttempt.last.reason
  end

  test "alg none: no session" do
    hand_off(JWT.encode(hub_claims(@legacy.email), nil, "none"))
    assert_not signed_in?
    assert_equal "bad_algorithm", EmailHandoffAttempt.last.reason
  end

  test "a replayed assertion signs nobody in" do
    token = hub_assertion(@legacy.email)
    hand_off(token)
    assert signed_in?

    reset!
    hand_off(token)
    assert_redirected_to root_path
    assert_not signed_in?
    assert_equal "replayed", EmailHandoffAttempt.last.reason
  end

  test "an unknown address lands on Play Now with the ref, signed out, and no account is made" do
    assert_no_difference -> { User.count } do
      hand_off(hub_assertion("stranger@example.com", ref: "hub-delivery-token-0044"))
    end
    assert_redirected_to root_path
    assert_equal "hub-delivery-token-0044", cookies[:email_ref]
    assert_not signed_in?
    assert_equal "no_account", EmailHandoffAttempt.last.outcome
  end

  test "an admin's address is refused: admins sign in with a magic link" do
    admin = player("boss", piece_skin: "vector", email_updates: true)
    admin.update_columns(role: "admin")
    hand_off(hub_assertion(admin.email))
    assert_redirected_to login_path
    assert_not signed_in?
    attempt = EmailHandoffAttempt.last
    assert_equal %w[rejected admin_account], [ attempt.outcome, attempt.reason ]
  end

  test "a guest's address never signs in to the guest" do
    guest = User.create_guest!
    guest.update_columns(email: "guest@example.com")
    hand_off(hub_assertion("guest@example.com"))
    assert_equal "no_account", EmailHandoffAttempt.last.outcome
  end

  test "a Play Now guest who signs in this way keeps their games" do
    post live_seeks_path
    guest = LiveSeek.last.user
    match = live_result(guest, Match.computer_player(rng: Random.new(1)), winner: guest)

    hand_off(hub_assertion(@legacy.email))
    assert_equal @legacy, match.reload.home_user
    assert_nil User.find_by(id: guest.id)
  end

  test "a player already signed in the normal way keeps the stronger session" do
    arya = player("arya", piece_skin: "vector", email_updates: true)
    log_in_as(arya)
    hand_off(hub_assertion(arya.email))
    patch profile_path, params: { profile: { email: "arya.new@example.com" } }
    assert_equal "arya.new@example.com", arya.reload.email, "no re-confirmation was asked for"
  end

  test "without MS_HANDOFF_PUBLIC_KEY it fails closed: Play Now, no session, a named error" do
    ENV[EmailHandoff::KEY_ENV] = nil
    assert_difference -> { ErrorLog.where("message LIKE ?", "%MS_HANDOFF_PUBLIC_KEY%").count }, 1 do
      hand_off(hub_assertion(@legacy.email))
    end
    assert_redirected_to root_path
    assert_not signed_in?
    assert_equal "not_configured", EmailHandoffAttempt.last.reason
  end

  test "rate limited per address" do
    EmailHandoffsController::RATE.times { hand_off("x") }
    assert_redirected_to root_path
    hand_off(hub_assertion(@legacy.email))
    assert_response :too_many_requests
    assert_not signed_in?
    assert_equal "rate_limited", EmailHandoffAttempt.last.reason
  end

  test "the assertion never reaches the log" do
    token = hub_assertion(@legacy.email)
    log = Rails.root.join("log/test.log")
    offset = File.size(log)
    hand_off(token, return_to: "/matches")
    written = File.read(log).byteslice(offset..)
    assert_includes written, "/auth/email_handoff", "the request was logged"
    assert_not_includes written, token.split(".").last
    assert_not_includes written, token.split(".").first(2).join(".")
  end

  test "assertion is a filtered parameter" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal({ "assertion" => "[FILTERED]", "return_to" => "/x" }, filter.filter("assertion" => "eyJ.x.y", "return_to" => "/x"))
  end
end
