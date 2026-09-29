require "test_helper"

# [integration] A session an email handoff started (ConfirmedSession) may play,
# chat and onboard, but changing the email or a sign-in method asks for a
# fresh magic link first; the link's click confirms the session.
class ConfirmedSessionTest < ActionDispatch::IntegrationTest
  include HubAssertions
  include LiveResults

  setup do
    @previous_key = ENV[EmailHandoff::KEY_ENV]
    ENV[EmailHandoff::KEY_ENV] = hub_public_pem
    EmailHandoffsController::RATE_STORE.clear
    @arya = player("arya", piece_skin: "vector", email_updates: true)
    OmniAuth.config.test_mode = true
  end

  teardown do
    ENV[EmailHandoff::KEY_ENV] = @previous_key
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def hand_off
    get email_handoff_path, params: { assertion: hub_assertion(@arya.email) }
  end

  def confirmation_links
    Studio::Link.magic_links.select { |link| link.return_to.to_s.start_with?("/account/confirm?") }
  end

  def change_email
    patch profile_path, params: { profile: { email: "arya.new@example.com" } }
  end

  test "a handoff session may play and chat" do
    hand_off
    get matches_path
    assert_response :success
    patch username_path, params: { username: "arya_stark" }
    assert_equal "arya_stark", @arya.reload.username
  end

  test "changing the email demands a fresh magic link, and changes nothing" do
    hand_off
    assert_difference -> { confirmation_links.size }, 1 do
      change_email
    end
    assert_redirected_to root_path
    assert_match "confirm it's you", flash[:alert]
    assert_equal "arya@example.com", @arya.reload.email
    assert_equal "arya@example.com", confirmation_links.last.email
  end

  test "unlinking Google demands a fresh magic link" do
    @arya.update!(provider: "google_oauth2", uid: "g-arya")
    hand_off
    delete profile_unlink_google_path
    assert_redirected_to root_path
    assert_equal [ "google_oauth2", "g-arya" ], @arya.reload.slice(:provider, :uid).values
    assert_equal 1, confirmation_links.size
  end

  test "adding Google demands a fresh magic link" do
    hand_off
    OmniAuth.config.mock_auth[:google_oauth2] =
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-arya", info: { email: @arya.email, name: "Arya" })
    post "/auth/google_oauth2"
    follow_redirect!
    assert_redirected_to root_path
    assert_nil @arya.reload.provider
    assert_equal 1, confirmation_links.size
  end

  test "one confirmation email per couple of minutes" do
    hand_off
    change_email
    change_email
    assert_equal 1, confirmation_links.size
  end

  test "the link clicked in this browser confirms the session, and the change goes through" do
    hand_off
    change_email
    link = confirmation_links.last

    post link_consume_path(token: link.token)
    assert_redirected_to link.return_to
    follow_redirect!
    assert_redirected_to root_path
    assert_equal "Confirmed. You can change how you sign in now.", flash[:notice]

    change_email
    assert_equal "arya.new@example.com", @arya.reload.email
  end

  test "the link clicked in another browser signs that browser in normally" do
    hand_off
    change_email
    link = confirmation_links.last

    other = open_session
    other.post link_consume_path(token: link.token)
    other.follow_redirect!
    other.patch profile_path, params: { profile: { email: "arya.other@example.com" } }
    assert_equal "arya.other@example.com", @arya.reload.email
  end

  test "a forged or foreign confirmation token confirms nothing" do
    hand_off
    get confirm_session_path(t: "forged")
    assert_redirected_to root_path
    bran = player("bran")
    get confirm_session_path(t: ConfirmedSession.token_for(bran))
    change_email
    assert_equal "arya@example.com", @arya.reload.email
  end

  test "an expired confirmation token confirms nothing" do
    hand_off
    token = ConfirmedSession.token_for(@arya)
    travel ConfirmedSession::LINK_LIFE + 1.minute do
      get confirm_session_path(t: token)
      change_email
    end
    assert_equal "arya@example.com", @arya.reload.email
  end

  test "an ordinary magic-link session is never asked" do
    log_in_as(@arya)
    change_email
    assert_equal "arya.new@example.com", @arya.reload.email
    assert_empty confirmation_links
  end

  test "signing in to another account starts a normal session" do
    hand_off
    bran = player("bran", piece_skin: "vector", email_updates: true)
    log_in_as(bran)
    patch profile_path, params: { profile: { email: "bran.new@example.com" } }
    assert_equal "bran.new@example.com", bran.reload.email
  end
end
