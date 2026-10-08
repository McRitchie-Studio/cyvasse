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

  # A poll already on its way when the player leaves the board must not pull
  # them off the page they went to (a Turbo visit keeps this page's scripts).
  test "a poll answered after the player left the board does not move them" do
    match = play_now_match
    visit match_path(match)
    assert_controllers_connected "cyvasse-match"
    page.execute_script(<<~JS)
      const real = window.fetch
      window.held = []
      window.fetch = (url, options) => String(url).includes("/matches/") && !options?.method
        ? new Promise((resolve) => window.held.push(() => resolve(real(url, options).finally(() => setTimeout(() => { window.answered = true }, 1000)))))
        : real(url, options)
    JS
    js = ->(script) { page.document.synchronize { page.evaluate_script(script) || raise(Capybara::ExpectationNotMet, script) } }
    js.("window.held.length > 0")
    page.execute_script("Turbo.visit(#{play_path.to_json})")
    assert_no_selector BOARD
    match.withdraw!(@brienne)
    page.execute_script("window.held.splice(0).forEach((answer) => answer())")
    js.("window.answered === true")
    assert_current_path play_path
  end
end
