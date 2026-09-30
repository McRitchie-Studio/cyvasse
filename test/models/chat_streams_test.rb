require "test_helper"

# [unit] ChatStreams: the chat's stream names, and that each is heard only by
# the people it belongs to (task cyvasse-live-chat).
class ChatStreamsTest < ActiveSupport::TestCase
  User2 = Struct.new(:id)

  setup do
    @arya, @brienne, @cersei = User2.new(7), User2.new(3), User2.new(12)
  end

  test "names: one per player, one per unordered pair" do
    assert_equal "chat:user:7", ChatStreams.user(@arya)
    assert_equal "chat:pair:3-7", ChatStreams.pair(@arya, @brienne)
    assert_equal ChatStreams.pair(@arya, @brienne), ChatStreams.pair(@brienne, @arya)
    assert_equal "chat_thread_3_7", ChatStreams.thread_id(@arya, @brienne)
  end

  test "a player's own stream is theirs alone" do
    assert ChatStreams.permitted?("chat:user:7", @arya)
    assert_not ChatStreams.permitted?("chat:user:7", @brienne)
    assert_not ChatStreams.permitted?("chat:user:7", nil)
  end

  test "a pair's stream is its two players' alone" do
    assert ChatStreams.permitted?("chat:pair:3-7", @arya)
    assert ChatStreams.permitted?("chat:pair:3-7", @brienne)
    assert_not ChatStreams.permitted?("chat:pair:3-7", @cersei)
    assert_not ChatStreams.permitted?("chat:pair:7-3", @arya), "only the canonical low-high name"
    assert_not ChatStreams.permitted?("chat:pair:7-7", @arya)
  end

  test "anything else is refused" do
    [ "chat:user:7x", "chat:user:", "gid://cyvasse/User/7", "chat:pair:3-7-9", "" ].each do |name|
      assert_not ChatStreams.permitted?(name, @arya), name
    end
  end
end
