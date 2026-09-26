require "test_helper"

# [unit] A message is readable by its two people and by admins, and nobody
# else; a match chat message goes to the sender's opponent in that match.
class MessageTest < ActiveSupport::TestCase
  include MatchPlay

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
    @cersei = make_player("cersei")
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin")
    @match = Match.challenge!(@arya, "brienne")
    @message = Message.post_in_match!(@match, @arya, "  Good luck!  ")
  end

  test "a match message goes from the sender to their opponent, trimmed and unread" do
    assert_equal [ @arya, @brienne, @match, "Good luck!", false ],
                 [ @message.sender, @message.receiver, @message.match, @message.message, @message.read ]
    reply = Message.post_in_match!(@match, @brienne, "You too")
    assert_equal @arya, reply.receiver
  end

  test "visibility is limited to participants and admins" do
    assert @message.readable_by?(@arya)
    assert @message.readable_by?(@brienne)
    assert @message.readable_by?(@admin)
    assert_not @message.readable_by?(@cersei)
    assert_not @message.readable_by?(nil)

    assert_includes Message.visible_to(@arya), @message
    assert_includes Message.visible_to(@brienne), @message
    assert_includes Message.visible_to(@admin), @message
    assert_empty Message.visible_to(@cersei)
    assert_empty Message.visible_to(nil)
  end

  test "only a player of the match can post in its chat" do
    error = assert_raises(Match::Refused) { Message.post_in_match!(@match, @cersei, "hi") }
    assert_match(/not playing/, error.message)
  end

  test "a match message must be between the match's two players" do
    message = Message.new(sender: @arya, receiver: @cersei, match: @match, message: "psst")
    assert_not message.valid?
    assert_includes message.errors[:match], "is not between these two players"
  end

  test "a new message needs text, no longer than the limit, to someone else" do
    assert_raises(ActiveRecord::RecordInvalid) { Message.post_in_match!(@match, @arya, "   ") }
    assert_raises(ActiveRecord::RecordInvalid) { Message.post_in_match!(@match, @arya, "x" * (Message::MAX_LENGTH + 1)) }
    to_self = Message.new(sender: @arya, receiver: @arya, message: "me")
    assert_not to_self.valid?
    assert_includes to_self.errors[:receiver], "must be someone else"
  end

  test "a legacy row is kept as it is: blank and matchless" do
    legacy = Message.new(sender: @arya, receiver: @brienne, message: nil, legacy_id: 7)
    legacy.save!(validate: false)
    assert legacy.reload.persisted?
    assert_raises(ActiveRecord::RecordNotUnique) do
      Message.new(sender: @arya, receiver: @brienne, message: "x", legacy_id: 7).save!(validate: false)
    end
  end

  test "mark_read! marks only the reader's own incoming messages" do
    Message.post_in_match!(@match, @brienne, "thanks")
    assert_equal 1, Message.mark_read!(@match.messages, @brienne)
    assert @message.reload.read
    assert_equal 1, Message.unread_by(@arya).count, "the reply to Arya is still unread"
  end

  test "a deleted match leaves its messages in the conversation" do
    @match.withdraw!(@arya)
    assert_nil @message.reload.match_id
    assert_includes Message.between(@arya, @brienne), @message
  end

  test "a player with messages is kept" do
    assert_not @arya.destroy
    assert @arya.reload.persisted?
  end
end
