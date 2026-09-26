require "test_helper"

# [unit] A conversation's messages grouped by the game they were sent in:
# groups newest first, messages oldest first inside each, messages outside
# any game in their own group, capped per group, a page of groups at a time,
# and one game paged whole, in a fixed number of queries.
class ConversationThreadTest < ActiveSupport::TestCase
  include MatchPlay

  setup do
    @arya, @brienne, @cersei = %w[arya brienne cersei].map { make_player(_1) }
    @old_game = Match.challenge!(@arya, "brienne")
    @new_game = Match.challenge!(@brienne, "arya")
  end

  def say(from, to, text, at:, match: nil)
    Message.create!(sender: from, receiver: to, message: text, match: match, created_at: at, updated_at: at)
  end

  def thread(**sizes) = ConversationThread.new(@arya, @brienne, **sizes)

  test "groups by game, newest group first, oldest message first inside each" do
    say(@arya, @brienne, "old 1", at: 10.days.ago, match: @old_game)
    say(@brienne, @arya, "old 2", at: 9.days.ago, match: @old_game)
    say(@brienne, @arya, "outside", at: 5.days.ago)
    say(@arya, @brienne, "new 2", at: 1.day.ago, match: @new_game)
    say(@brienne, @arya, "new 1", at: 2.days.ago, match: @new_game)
    say(@arya, @cersei, "someone else", at: 1.hour.ago)

    page = thread.page(1)
    assert_equal 5, thread.total
    assert_equal [ @new_game.id.to_s, "none", @old_game.id.to_s ], page.groups.map(&:key)
    assert_equal [ %w[new\ 1 new\ 2], %w[outside], %w[old\ 1 old\ 2] ], page.groups.map { _1.messages.map(&:message) }
    assert_equal [ @new_game, nil, @old_game ], page.groups.map(&:match)
    newest = page.groups.first
    assert_equal [ 2, true, 0 ], [ newest.count, newest.complete?, newest.earlier_count ]
    assert_in_delta 2.days.ago, newest.first_at, 1
    assert_in_delta 1.day.ago, newest.last_at, 1
  end

  test "reads the pair from either side and never another pair's messages" do
    say(@arya, @brienne, "hi", at: 1.hour.ago)
    say(@brienne, @cersei, "not ours", at: 1.minute.ago)

    assert_equal [ "hi" ], ConversationThread.new(@brienne, @arya).page(1).groups.flat_map(&:messages).map(&:message)
  end

  test "shows each group's latest messages and counts the earlier ones" do
    5.times { |i| say(@arya, @brienne, "m#{i}", at: (10 - i).hours.ago, match: @old_game) }

    group = thread(per_group: 2).page(1).groups.sole
    assert_equal %w[m3 m4], group.messages.map(&:message)
    assert_equal [ 5, 3, 4, false ], [ group.count, group.earlier_count, group.first_number, group.complete? ]
  end

  test "pages the groups" do
    say(@arya, @brienne, "old", at: 2.days.ago, match: @old_game)
    say(@arya, @brienne, "new", at: 1.day.ago, match: @new_game)
    say(@arya, @brienne, "outside", at: 1.hour.ago)

    first = thread(groups_per_page: 2).page(1)
    assert_equal [ 3, 2, 2, nil ], [ first.total, first.pages, first.next_page, first.prev_page ]
    assert_equal [ "none", @new_game.id.to_s ], first.groups.map(&:key)
    last = thread(groups_per_page: 2).page("2")
    assert_equal [ @old_game.id.to_s ], last.groups.map(&:key)
    assert_equal [], thread(groups_per_page: 2).page(9).groups
    assert_equal 1, thread.page("junk").page
  end

  test "pages one game whole, oldest first" do
    5.times { |i| say(@arya, @brienne, "m#{i}", at: (10 - i).hours.ago, match: @old_game) }
    say(@arya, @brienne, "outside", at: 1.hour.ago)

    first = thread(per_page: 2).game(@old_game.id.to_s, page: 1)
    assert_equal [ 5, 3, 2 ], [ first.total, first.pages, first.next_page ]
    assert_equal %w[m0 m1], first.groups.sole.messages.map(&:message)
    last = thread(per_page: 2).game(@old_game.id, page: 3).groups.sole
    assert_equal [ %w[m4], 5, @old_game ], [ last.messages.map(&:message), last.first_number, last.match ]
    assert_equal [ "outside" ], thread.game("none").groups.sole.messages.map(&:message)
  end

  test "a game outside this conversation is nil" do
    say(@arya, @brienne, "hi", at: 1.hour.ago, match: @old_game)
    assert_nil thread.game(@new_game.id)
    assert_nil thread.game("none")
    assert_nil thread.game("junk")
  end

  test "loads a page in a fixed number of queries whatever the number of games" do
    6.times do |n|
      game = Match.create!(home_user: @arya, away_user: @brienne, match_status: Match::FINISHED, winner: @brienne, finish_reason: "king")
      3.times { |i| say(i.even? ? @arya : @brienne, i.even? ? @brienne : @arya, "g#{n} m#{i}", at: (n * 10 + i).minutes.ago, match: game) }
    end

    queries = count_queries do
      thread.page(1).groups.each { |group| group.match&.winner&.player_name && group.messages.map { _1.sender.player_name } }
    end
    assert_operator queries, :<=, 5
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
