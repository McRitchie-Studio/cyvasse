require "application_system_test_case"

# [e2e] A live match that ends while its page is open opens the game-over
# modal, however it ends, and the in-game controls follow the phase (task
# cyvasse-game-over-modal-missing). Clocks are moved by rewinding
# clock_started_at; the open page's own polls settle them.
class LiveGameOverTest < ApplicationSystemTestCase
  MODAL = "[data-test=game-over-modal]".freeze
  BOARD = "[data-controller=cyvasse-match]".freeze

  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @match = Match.start_live!(@arya, computer: true, rng: Random.new(4))
    visit link_path(token: Studio::Link.create_magic_link(email: @arya.email).token)
    assert_text "Signed in as Arya"
  end

  test "a seat the computer took over loses with the page open: the modal opens and the controls go" do
    visit match_path(@match)
    assert_button "Forfeit match"

    @match.set_up!(@arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    assert_selector "#{BOARD}[data-phase=play]", wait: 10
    assert_button "Forfeit match"

    # Arya misses two move clocks; the computer takes her seat.
    until @match.reload.taken_over?(:home) || @match.finished?
      if @match.seat_to_move == :home
        @match.update_columns(clock_started_at: 31.seconds.ago)
      elsif @match.bot_due_at
        @match.update_columns(bot_due_at: 1.second.ago)
      end
      sleep 0.5
    end
    skip "the game ended before the takeover" if @match.finished?
    assert_text "a computer player has taken your seat", wait: 5
    assert_no_selector MODAL

    # The two computers play it out while the page watches.
    rng = Random.new(7)
    until @match.reload.finished?
      due = @match.bot_due_at || Time.current
      travel_to(due + 1.second) { @match.tick!(rng:) }
    end

    within(MODAL, wait: 10) { assert_selector "h3", text: /king|draw/i }
    assert_no_button "Forfeit match"
  end

  test "a resignation with the page open opens the modal and hides Forfeit match" do
    @match.set_up!(@arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    visit match_path(@match)
    assert_button "Forfeit match"
    assert_no_selector MODAL

    @match.reload.resign!(@arya)

    within(MODAL, wait: 10) { assert_selector "h3", text: "You resigned." }
    assert_no_button "Forfeit match"
  end

  test "an opponent's forfeit that lands while the player is away opens the modal when they come back" do
    @match.set_up!(@arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    visit match_path(@match)
    assert_button "Forfeit match"
    # Another tab, window or app: hidden and without focus.
    page.execute_script(<<~JS)
      Object.defineProperty(document, "visibilityState", { value: "hidden", configurable: true })
      document.hasFocus = () => false
    JS

    @match.reload.send(:finish!, winner: @arya, reason: "forfeit")
    assert_selector "[data-cyvasse-match-target=status]", text: "Your opponent ran out of time. You win.", wait: 10
    assert_no_selector MODAL
    assert_no_button "Forfeit match"

    page.execute_script(<<~JS)
      delete document.visibilityState
      delete document.hasFocus
      document.dispatchEvent(new Event("visibilitychange"))
    JS
    within(MODAL, wait: 5) { assert_selector "h3", text: "Your opponent ran out of time. You win." }
  end

  test "a finished match opened from My games shows its result without the modal" do
    @match.set_up!(@arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    @match.reload.resign!(@arya)
    @match.update_columns(finished_at: 2.days.ago)

    visit matches_path
    visit match_path(@match)
    assert_selector "[data-cyvasse-match-target=status]", text: "You resigned."
    sleep 1.5 # a poll's worth
    assert_no_selector MODAL
    assert_no_button "Forfeit match"
  end
end
