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

  # The engine's device-session check (Studio::UserSession.ended?) is stubbed so
  # these run on an engine with or without the helper; the engine's own suite
  # proves which cookies it calls ended.
  def with_device_session_verdict(ended)
    seen = []
    klass = Studio::UserSession.singleton_class
    had = klass.method_defined?(:ended?)
    klass.alias_method(:ended_before_stub?, :ended?) if had
    klass.define_method(:ended?) { |store, **| seen << store; ended }
    yield seen
  ensure
    klass.remove_method(:ended?)
    if had
      klass.alias_method(:ended?, :ended_before_stub?)
      klass.remove_method(:ended_before_stub?)
    end
  end

  test "refuses a logged-out device's cookie (an ended device session)" do
    guest = User.create_guest!
    session_cookie(Studio.session_key.to_s => guest.id)
    with_device_session_verdict(true) do |seen|
      assert_reject_connection { connect }
      assert_equal guest.id, seen.last[Studio.session_key.to_s], "the check reads the decoded cookie"
    end
  end

  test "connects a live device session as its player" do
    guest = User.create_guest!
    session_cookie(Studio.session_key.to_s => guest.id)
    with_device_session_verdict(false) do |seen|
      connect
      assert_equal guest, connection.current_user
      assert_equal 1, seen.size
    end
  end

  test "a socket with no player is refused before the device-session check reads anything" do
    with_device_session_verdict(false) do |seen|
      assert_reject_connection { connect }
      assert_empty seen
    end
  end

  test "on an engine without the helper the guard is a no-op" do
    klass = Studio::UserSession.singleton_class
    had = klass.method_defined?(:ended?)
    klass.alias_method(:ended_hidden?, :ended?) if had
    klass.remove_method(:ended?) if had
    assert_not Studio::UserSession.respond_to?(:ended?)

    guest = User.create_guest!
    session_cookie(Studio.session_key.to_s => guest.id)
    connect
    assert_equal guest, connection.current_user
  ensure
    if had
      klass.alias_method(:ended?, :ended_hidden?)
      klass.remove_method(:ended_hidden?)
    end
  end
end
