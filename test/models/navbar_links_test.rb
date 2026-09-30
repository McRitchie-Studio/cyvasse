require "test_helper"

# [unit] NavbarLinks, the navbar's own links (task cyvasse-nav-links): My games
# only for a player who can open /matches, Chat for any signed-in player with
# their unread count as a badge (task cyvasse-live-chat), Leaderboard always,
# with a "#N" badge from Leaderboard.rank_for and none when the player is not
# on the board.
class NavbarLinksTest < ActiveSupport::TestCase
  include LiveResults

  View = Struct.new(:current_user)

  def links(user) = Studio::NavbarLinks.resolve(->(view) { NavbarLinks.call(view) }, View.new(user))
  def labels(user) = links(user).map { |link| link[:label] }
  def leaderboard(user) = links(user).find { |link| link[:label] == "Leaderboard" }
  def chat(user) = links(user).find { |link| link[:label] == "Chat" }

  test "a signed-out visitor gets the Leaderboard alone, with no badge" do
    assert_equal [ "Leaderboard" ], labels(nil)
    assert_nil leaderboard(nil)[:badge]
  end

  test "a view without current_user (an engine page) still resolves" do
    assert_equal [ "Leaderboard" ], Studio::NavbarLinks.resolve(->(view) { NavbarLinks.call(view) }, Object.new).map { _1[:label] }
  end

  test "a signed-in player without a username does not get My games, but gets Chat" do
    user = User.create!(email: "nameless@example.com", name: "Nameless")

    assert_equal [ "Chat", "Leaderboard" ], labels(user)
  end

  test "a player with a username gets My games, Chat, then Leaderboard" do
    assert_equal [ "My games", "Chat", "Leaderboard" ], labels(player("arya"))
    assert_equal [ "/matches", "/conversations", "/leaderboard" ], links(player("brienne")).map { _1[:href] }
  end

  test "the Chat badge counts unread messages from people: none hidden, then N, then 9+" do
    arya, brienne = player("arya"), player("brienne")
    match = Match.challenge!(brienne, "arya")
    assert_nil chat(arya)[:badge], "no unread messages, no badge"

    3.times { |i| Message.post_in_match!(match, brienne, "hello #{i}") }
    assert_equal "3", chat(arya)[:badge]
    assert_nil chat(brienne)[:badge], "the sender's own messages do not count"

    7.times { |i| Message.post_in_match!(match, brienne, "more #{i}") }
    assert_equal "9+", chat(arya)[:badge]

    Message.mark_read!(Message.all, arya)
    assert_nil chat(arya)[:badge]
  end

  test "a computer player's messages never reach the Chat badge" do
    arya, bot = player("arya"), computer
    match = Match.create!(home_user: bot, away_user: arya, match_status: Match::IN_PROGRESS)
    Message.post_in_match!(match, bot, "Luck is for dice.")

    assert_equal 0, arya.unread_messages_count
    assert_nil chat(arya)[:badge]
  end

  test "the Leaderboard badge is the player's live rank" do
    arya, brienne = player("arya"), player("brienne")
    live_result(arya, brienne, winner: arya)

    assert_equal "#1", leaderboard(arya)[:badge]
    assert_equal "#2", leaderboard(brienne)[:badge]
  end

  test "a player not on the board gets no badge" do
    assert_nil leaderboard(player("arya"))[:badge]
  end

  test "a failed rank query degrades to no badge and is logged, not raised" do
    arya = player("arya")
    original = Leaderboard.method(:rank_for)
    Leaderboard.define_singleton_method(:rank_for) do |_user|
      raise ActiveRecord::StatementInvalid, "PG::QueryCanceled: statement timeout"
    end

    resolved = assert_difference(-> { ErrorLog.count }, 1) { links(arya) }

    assert_equal [ "My games", "Chat", "Leaderboard" ], resolved.map { _1[:label] }
    assert_nil resolved.last[:badge]
    assert_match "statement timeout", ErrorLog.last.message
  ensure
    Leaderboard.define_singleton_method(:rank_for, original)
  end

  test "active patterns cover the index and the pages under it, not lookalikes" do
    my_games, chat, board = NavbarLinks.call(View.new(player("arya"))).map { _1[:active] }

    assert_match my_games, "/matches"
    assert_match my_games, "/matches/42"
    assert_no_match my_games, "/matchesx"
    assert_match chat, "/conversations"
    assert_match chat, "/conversations/7"
    assert_no_match chat, "/conversationsx"
    assert_match board, "/leaderboard"
    assert_match board, "/leaderboard/join"
    assert_no_match board, "/leaderboards"
  end

  test "the links cost two queries: the rank and the unread count" do
    arya = player("arya")
    live_result(arya, computer, winner: arya)
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { links(arya) }

    assert_equal 2, queries.size, queries.join("\n")
  end
end
