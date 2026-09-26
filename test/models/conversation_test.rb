require "test_helper"

# [unit] Conversations are the unordered pairs of messages' two people:
# newest first, searchable by player, a page at a time, in a fixed number of
# queries.
class ConversationTest < ActiveSupport::TestCase
  include MatchPlay

  setup do
    @arya, @brienne, @cersei, @davos = %w[arya brienne cersei davos].map { make_player(_1) }
  end

  def say(from, to, text, at:, match: nil)
    Message.create!(sender: from, receiver: to, message: text, match: match, created_at: at, updated_at: at)
  end

  test "groups both directions of a pair into one conversation, newest first" do
    say(@arya, @brienne, "one", at: 3.hours.ago)
    say(@brienne, @arya, "two", at: 1.hour.ago)
    say(@cersei, @davos, "three", at: 2.hours.ago)

    page = Conversation.page(Message.all)
    assert_equal 2, page.total
    first, second = page.conversations
    assert_equal [ @arya, @brienne ], first.users
    assert_equal [ 2, "two" ], [ first.messages_count, first.last_message.message ]
    assert_equal [ @cersei, @davos ], second.users
    assert_equal "#{@arya.id}-#{@brienne.id}", first.key
    assert_equal @brienne, first.other(@arya)
  end

  test "the last message is the latest by time, not by id" do
    say(@arya, @brienne, "later", at: 1.minute.ago)
    say(@brienne, @arya, "imported late but older", at: 1.year.ago)
    assert_equal "later", Conversation.page(Message.all).conversations.first.last_message.message
  end

  test "counts what the reader has not read, and lists each conversation's matches" do
    match = Match.challenge!(@arya, "brienne")
    say(@arya, @brienne, "hi", at: 2.minutes.ago, match: match)
    say(@arya, @brienne, "you there?", at: 1.minute.ago)
    say(@brienne, @arya, "yes", at: 30.seconds.ago)

    conversation = Conversation.page(Message.involving(@brienne), reader: @brienne).conversations.sole
    assert_equal 2, conversation.unread_count
    assert conversation.unread?
    assert_equal [ match ], conversation.matches
    assert_equal 0, Conversation.page(Message.all).conversations.sole.unread_count, "no reader, no count"
  end

  test "a player's scope shows only their conversations" do
    say(@arya, @brienne, "a", at: 1.minute.ago)
    say(@cersei, @davos, "b", at: 1.minute.ago)
    assert_equal [ [ @arya, @brienne ] ], Conversation.page(Message.involving(@brienne)).conversations.map(&:users)
  end

  test "searches by username, name or email, in any case, on either side" do
    say(@arya, @brienne, "a", at: 2.minutes.ago)
    say(@cersei, @davos, "b", at: 1.minute.ago)
    @davos.update!(name: "Onion Knight")

    assert_equal 1, Conversation.page(Conversation.for_players("BRIEN")).total
    assert_equal 1, Conversation.page(Conversation.for_players("onion")).total
    assert_equal 1, Conversation.page(Conversation.for_players("arya@example")).total
    assert_equal 0, Conversation.page(Conversation.for_players("nobody")).total
    assert_equal 0, Conversation.page(Conversation.for_players("%")).total, "a LIKE wildcard is literal"
    assert_equal 2, Conversation.page(Conversation.for_players("  ")).total
  end

  test "pages through conversations" do
    players = Array.new(5) { |n| make_player("player#{n}") }
    players.each_with_index { |p, n| say(@arya, p, "hi #{n}", at: n.minutes.ago) }

    first = Conversation.page(Message.all, page: 1, per_page: 2)
    assert_equal [ 5, 3, 2, nil, 1, 2 ], [ first.total, first.pages, first.next_page, first.prev_page, first.first_number, first.last_number ]
    assert_equal [ "hi 0", "hi 1" ], first.conversations.map { _1.last_message.message }

    last = Conversation.page(Message.all, page: 3, per_page: 2)
    assert_equal [ "hi 4" ], last.conversations.map { _1.last_message.message }
    assert_equal [ nil, 2, 5, 5 ], [ last.next_page, last.prev_page, last.first_number, last.last_number ]
    assert_equal 1, Conversation.page(Message.all, page: "junk").page
  end

  test "loads a page in a fixed number of queries" do
    players = Array.new(6) { |n| make_player("player#{n}") }
    players.each { |p| say(@arya, p, "hi", at: 1.minute.ago, match: Match.challenge!(@arya, p.username)) }

    queries = count_queries { Conversation.page(Message.all).conversations.each { _1.users.map(&:username) + _1.matches.map(&:id) } }
    assert_operator queries, :<=, 5
  end

  test "parses a pair key" do
    assert_equal [ 3, 12 ], Conversation.parse_key("12-3")
    assert_nil Conversation.parse_key("12")
    assert_nil Conversation.parse_key("a-b")
    assert_nil Conversation.parse_key("1-2-3")
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
