require "application_system_test_case"

# [component] The live match board (LiveMatch + cyvasse_match_controller): the
# clock both players see, the ten-second nudge, an army placed by the clock
# arriving piece by piece, the computer opponent's tag and "thinking", and
# the strike notice. Clocks are moved by rewinding clock_started_at.
class LiveMatchUiTest < ApplicationSystemTestCase
  BOARD = "[data-controller=cyvasse-match]".freeze

  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @match = Match.start_live!(@arya, computer: true, rng: Random.new(4))
    visit link_path(token: Studio::Link.create_magic_link(email: @arya.email).token)
    assert_text "Signed in as Arya"
  end

  def rewind_clock(seconds)
    @match.reload.update_columns(clock_started_at: Time.current - seconds)
  end

  test "the setup clock counts down, and a computer opponent is tagged with no chat" do
    visit match_path(@match)
    assert_selector "[data-cyvasse-match-target=clock]", visible: true
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: "Set up your army"
    assert_selector "[data-cyvasse-match-target=clockSeconds]", text: /\A(59|60)s\z/
    assert_selector ".live-computer-tag", text: /computer/i
    assert_text @match.display_name_of(@match.away_user)
    assert_no_text "Chat with"
    assert_no_selector "[data-cyvasse-match-target=deadline]", visible: true
  end

  test "ten seconds from the end the player is told to hurry" do
    rewind_clock(52)
    visit match_path(@match)
    assert_selector ".live-clock.is-warning [data-cyvasse-match-target=clockLabel]", text: "Hurry: set up your board!"
  end

  test "an army placed by the clock arrives on the board, and the player is told" do
    rewind_clock(58)
    visit match_path(@match)
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_text "Time ran out, so your army was placed for you.", wait: 10
    assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='1']", count: 19
    assert_selector "#{BOARD}[data-phase=play]"
    assert @match.reload.home_auto_set_up?
  end

  test "a missed move clock plays a move for you and says so" do
    @match.set_up!(@arya, CyvasseRules::Bot.random_lineup(rng: Random.new(2)))
    @match.reload
    unless @match.seat_to_move == :home
      travel_to(@match.bot_due_at + 1) { @match.tick! }
      @match.reload
    end
    skip "the computer won on its first move" if @match.finished?
    rewind_clock(29)
    visit match_path(@match)
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: /Your move|Hurry/
    assert_text "You missed a clock", wait: 10
    assert_equal 1, @match.reload.home_strikes
  end

  test "the live poll mid-setup keeps the army the player has placed" do
    visit match_path(@match)
    click_on "Random Setup"
    assert_no_selector ".cyvasse-dock .dock-unit"
    # The opponent readying writes the match: a new version reaches the poll.
    travel(2.seconds) { @match.reload.touch }
    sleep 2.5 # two live polls land, one carrying the new version
    assert_no_selector ".cyvasse-dock .dock-unit"
    assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='1']", count: 19
  end

  test "while the computer is to move, the player sees it thinking" do
    @match.set_up!(@arya, CyvasseRules::Bot.random_lineup(rng: Random.new(2)))
    @match.reload
    @match.update_columns(whos_turn: Match::AWAY, bot_due_at: 1.hour.from_now) unless @match.seat_to_move == :away
    visit match_path(@match)
    assert_selector ".live-clock.is-thinking [data-cyvasse-match-target=clockLabel]",
                    text: "#{@match.display_name_of(@match.away_user)} is thinking…"
  end
end
