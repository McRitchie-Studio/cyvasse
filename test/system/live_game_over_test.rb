require "application_system_test_case"

# [e2e] A live match that ends while its page is open opens the game-over
# modal, however it ends, and the in-game controls go (task
# cyvasse-game-over-modal-missing). Clocks are moved by rewinding
# clock_started_at and bot_due_at; the open page's own polls settle them.
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
    assert_button "Cancel match"

    # Clock one: the setup runs out and the army is placed for Arya.
    @match.reload.update_columns(clock_started_at: 61.seconds.ago)
    assert_selector "#{BOARD}[data-phase=play]", wait: 10
    # Clock two: Arya's move runs out and the computer takes the seat.
    until @match.reload.taken_over?(:home) || @match.finished?
      if @match.seat_to_move == :home
        @match.update_columns(clock_started_at: 31.seconds.ago)
      else
        @match.update_columns(bot_due_at: 1.second.ago) if @match.bot_due_at
      end
      sleep 0.5
    end
    skip "the game ended before the takeover" if @match.finished?
    assert_text "a computer player has taken your seat", wait: 5
    assert_no_selector MODAL

    # The two computers play it out on the server while the page watches.
    rng = Random.new(7)
    until @match.reload.finished?
      due = @match.bot_due_at || Time.current
      travel_to(due + 1.second) { @match.tick!(rng:) }
    end

    within(MODAL, wait: 10) { assert_selector "h3", text: /\S/ }
    assert_no_button "Cancel match"
    assert_no_button "Resign"
  end

  test "a resignation on the server with the page open opens the modal and hides Resign" do
    @match.set_up!(@arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    visit match_path(@match)
    assert_button "Resign"
    assert_no_selector MODAL

    @match.reload.resign!(@arya)

    within(MODAL, wait: 10) { assert_selector "h3", text: "You resigned." }
    assert_no_button "Resign"
  end

  test "a finished match opened from My games shows its result without the modal" do
    @match.set_up!(@arya, CyvasseRules::Bot.lineup(rng: Random.new(5)))
    @match.reload.resign!(@arya)
    @match.update_columns(finished_at: 2.days.ago, updated_at: 2.days.ago)

    visit matches_path
    visit match_path(@match)
    assert_selector "[data-cyvasse-match-target=status]", text: "You resigned."
    sleep 1.5 # a poll's worth
    assert_no_selector MODAL
  end
end
