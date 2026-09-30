require "test_helper"

# [integration] The websocket's player comes from the signed session cookie,
# as a page's does; no session, no socket (task cyvasse-live-chat).
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  include MatchPlay

  # The test jar takes a Hash as cookie options, so the session goes in :value.
  def session_cookie(data)
    cookies.encrypted[Rails.application.config.session_options[:key]] = { value: data }
  end

  test "connects as the session's player, a guest included" do
    guest = User.create_guest!
    session_cookie(Studio.session_key.to_s => guest.id)
    connect
    assert_equal guest, connection.current_user
  end

  test "refuses a socket with no signed-in player" do
    assert_reject_connection { connect }

    session_cookie(Studio.session_key.to_s => 0)
    assert_reject_connection { connect }
  end
end
