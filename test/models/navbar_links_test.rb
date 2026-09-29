require "test_helper"

# [unit] NavbarLinks, the navbar's own links (task cyvasse-nav-links): My games
# only for a player who can open /matches, Leaderboard always, with a "#N"
# badge from Leaderboard.rank_for and none when the player is not on the board.
class NavbarLinksTest < ActiveSupport::TestCase
  include LiveResults

  View = Struct.new(:current_user)

  def links(user) = Studio::NavbarLinks.resolve(->(view) { NavbarLinks.call(view) }, View.new(user))
  def labels(user) = links(user).map { |link| link[:label] }
  def leaderboard(user) = links(user).find { |link| link[:label] == "Leaderboard" }

  test "a signed-out visitor gets the Leaderboard alone, with no badge" do
    assert_equal [ "Leaderboard" ], labels(nil)
    assert_nil leaderboard(nil)[:badge]
  end

  test "a view without current_user (an engine page) still resolves" do
    assert_equal [ "Leaderboard" ], Studio::NavbarLinks.resolve(->(view) { NavbarLinks.call(view) }, Object.new).map { _1[:label] }
  end

  test "a signed-in player without a username does not get My games" do
    user = User.create!(email: "nameless@example.com", name: "Nameless")

    assert_equal [ "Leaderboard" ], labels(user)
  end

  test "a player with a username gets My games then Leaderboard" do
    assert_equal [ "My games", "Leaderboard" ], labels(player("arya"))
    assert_equal [ "/matches", "/leaderboard" ], links(player("brienne")).map { _1[:href] }
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

  test "active patterns cover the index and the pages under it, not lookalikes" do
    my_games, board = NavbarLinks.call(View.new(player("arya"))).map { _1[:active] }

    assert_match my_games, "/matches"
    assert_match my_games, "/matches/42"
    assert_no_match my_games, "/matchesx"
    assert_match board, "/leaderboard"
    assert_match board, "/leaderboard/join"
    assert_no_match board, "/leaderboards"
  end

  test "the links cost one query" do
    arya = player("arya")
    live_result(arya, computer, winner: arya)
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { links(arya) }

    assert_equal 1, queries.size, queries.join("\n")
  end
end
