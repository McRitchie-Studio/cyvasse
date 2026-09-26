require "test_helper"

# [unit] The demo seeder makes made-up conversations for the inbox and the
# admin page, is safe to run twice, and never runs in production.
class DemoConversationsTest < ActiveSupport::TestCase
  test "seeds conversations once, all between made-up players" do
    User.seed_identities!
    created = DemoConversations.seed!
    assert_operator created, :>, 0
    assert_operator Conversation.page(Message.all).total, :>, Conversation::PER_PAGE, "enough to page through"
    emails = User.where(id: Message.select(:sender_id)).or(User.where(id: Message.select(:receiver_id))).pluck(:email)
    assert emails.all? { _1.end_with?("@example.com") || _1 == "alex@mcritchie.studio" }, emails.inspect
    assert Message.where(legacy_id: nil).count == Message.count, "no legacy ids invented"

    assert_no_difference -> { Message.count } do
      assert_equal 0, DemoConversations.seed!
    end
  end

  test "refuses to run in production" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    assert_raises(RuntimeError) { DemoConversations.seed!(env: production) }
    assert_equal 0, Message.count
  end
end
