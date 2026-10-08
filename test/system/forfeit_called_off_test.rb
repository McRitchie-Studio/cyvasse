require "application_system_test_case"

# [e2e] A Play Now match called off during setup (task
# cyvasse-forfeit-match-answers-500): the player who forfeits lands on My
# games, and the other player's open board, whose match is gone, follows.
class ForfeitCalledOffTest < ApplicationSystemTestCase
  BOARD = "[data-controller=cyvasse-match]".freeze

  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne")
    visit link_path(token: Studio::Link.create_magic_link(email: @arya.email).token)
    assert_text "Signed in as arya"
  end

  def play_now_match
    LiveSeek.join!(@brienne)
    LiveSeek.join!(@arya).match
  end

  test "Forfeit match during setup calls the match off and lands on My games" do
    match = play_now_match
    visit match_path(match)
    assert_selector "#{BOARD}[data-phase=setup]"
    assert_controllers_connected "cyvasse-match"

    accept_confirm("Forfeit this match? It is called off before it starts.") { click_button "Forfeit match" }

    assert_current_path matches_path, wait: 15
    assert_selector "h1", text: "My games"
    assert_not Match.exists?(match.id)
  end

  test "the other player's open board leaves for My games when the match is called off" do
    match = play_now_match
    visit match_path(match)
    assert_selector "#{BOARD}[data-phase=setup]"
    assert_controllers_connected "cyvasse-match"

    match.withdraw!(@brienne)

    assert_current_path matches_path, wait: 15
    assert_selector "h1", text: "My games"
  end
end
