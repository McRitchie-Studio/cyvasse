require "test_helper"

# [integration] ChatStreamsChannel: a signed stream name is not enough; the
# subscriber must be the player it belongs to (task cyvasse-live-chat).
class ChatStreamsChannelTest < ActionCable::Channel::TestCase
  include MatchPlay

  setup do
    @arya, @brienne, @cersei = %w[arya brienne cersei].map { make_player(_1) }
  end

  def subscribe_as(user, name)
    stub_connection(current_user: user)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(name))
  end

  test "a player hears their own stream and their pairs' streams" do
    subscribe_as(@arya, ChatStreams.user(@arya))
    assert subscription.confirmed?
    assert_has_stream ChatStreams.user(@arya)

    subscribe_as(@brienne, ChatStreams.pair(@arya, @brienne))
    assert subscription.confirmed?
    assert_has_stream ChatStreams.pair(@arya, @brienne)
  end

  test "a validly signed name copied from someone else's page is refused" do
    subscribe_as(@cersei, ChatStreams.user(@arya))
    assert subscription.rejected?

    subscribe_as(@cersei, ChatStreams.pair(@arya, @brienne))
    assert subscription.rejected?
  end

  test "a forged or unsigned name is refused" do
    stub_connection(current_user: @arya)
    subscribe(signed_stream_name: "chat:user:#{@arya.id}")
    assert subscription.rejected?
  end
end
