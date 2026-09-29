require "application_system_test_case"

# [component] The live match board (LiveMatch + cyvasse_match_controller): the
# clock both players see, the ten-second nudge, an army placed by the clock
# arriving piece by piece, the computer opponent's tag and "thinking",
# the strike notice, and the computer's paced turn (its selection, its move,
# a cavalry unit's second jump). Clocks are moved by rewinding
# clock_started_at.
class LiveMatchUiTest < ApplicationSystemTestCase
  include MatchPlay
  include LiveBot

  BOARD = "[data-controller=cyvasse-match]".freeze

  teardown { LiveMatch.bot_pace = 0 }

  # A paced computer match (the computer away) with a cavalry double jump
  # planned for its turn.
  def computer_double_jump
    LiveMatch.bot_pace = 1
    match = Match.start_live!(@arya, computer: true, rng: Random.new(7))
    match.set_up!(@arya, home_lineup)
    match.reload
    if match.seat_to_move == :home
      game = match.to_game
      from = CyvasseRules::Bot.movers(game).find { |hex| !game.piece_at(hex).type.cavalry? && game.legal_actions(hex).moves.any? }
      match.play!(@arya, [ [ from, game.legal_actions(from).moves.first ] ])
      match.reload
    end
    plan_double_jump(match)
  end

  # Settle the computer's next step now, then hold the one after it until
  # the test asks: the page's own polls then only ever redraw.
  def next_bot_step(match)
    match.reload.update_columns(bot_due_at: 1.second.ago)
    match.tick!
    match.reload.update_columns(bot_due_at: 1.hour.from_now) if match.bot_plan
  end

  def hex(index) = "svg.cyvasse-board g.hex[data-hex='#{index}']"

  # Hold the computer's next turn past the end of the test. At pace 0 it
  # lands inside the very tick that settles the clock under test, before the
  # page draws that tick: from these armies it can take the player's units on
  # its first turn, or their king in reply to a move made for them.
  def hold_computer
    LiveMatch.bot_pace = 10_000
  end

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
    assert_selector ".match-versus-bot", text: "Computer"
    assert_text @match.display_name_of(@match.away_user)
    assert_no_text "Chat with"
    assert_no_selector "[data-cyvasse-match-target=deadline]", visible: true
  end

  test "[e2e] the versus card stacks you over the computer, its piece art beside its name, and fits a phone" do
    visit match_path(@match)
    them = @match.display_name_of(@match.away_user)
    assert_selector "h1.match-versus [data-side=me] [data-avatar=piece] img[src*='pieces/vector/']"
    assert_selector "h1.match-versus [data-side=them] [data-avatar=bot-fallback][aria-label='#{them}'] img[src*='pieces/vector/']"
    assert_selector "h1.match-versus [data-side=them]", text: them
    me, vs, bot = %w[[data-side=me]\ [data-avatar] .match-versus-vs [data-side=them]\ [data-avatar]].map do |css|
      page.evaluate_script("document.querySelector('h1.match-versus #{css}').getBoundingClientRect().top")
    end
    assert_operator me, :<, vs
    assert_operator vs, :<, bot
    page.save_screenshot(Rails.root.join("tmp/screenshots/versus-desktop.png")) if ENV["SCREENSHOTS"]

    # The phone viewport outlives the test in a shared browser: always undo it.
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 360, height: 800, deviceScaleFactor: 1, mobile: true)
    begin
      assert_selector "h1.match-versus [data-avatar=bot-fallback]"
      scroll, client = page_widths
      assert_operator scroll, :<=, client, "no sideways scroll at 360px"
      page.save_screenshot(Rails.root.join("tmp/screenshots/versus-phone.png")) if ENV["SCREENSHOTS"]
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end

  test "ten seconds from the end the player is told to hurry" do
    rewind_clock(52)
    visit match_path(@match)
    assert_selector ".live-clock.is-warning [data-cyvasse-match-target=clockLabel]", text: "Hurry: set up your board!"
  end

  test "an army placed by the clock arrives on the board, and the player is told" do
    hold_computer
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
    assert_equal :home, @match.seat_to_move, "both armies are seeded: the player moves first"
    # Without the hold, the computer's reply to the move made for the player
    # takes their king in the same tick, and the game-over modal hides the notice.
    hold_computer
    rewind_clock(29)
    visit match_path(@match)
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: /Your move|Hurry/
    assert_text "You missed a clock", wait: 10
    @match.reload
    assert_equal 1, @match.home_strikes
    assert_equal :away, @match.seat_to_move, "a move was made for the player"
    assert_not @match.finished?
  end

  test "the live poll mid-setup keeps the army the player has placed" do
    visit match_path(@match)
    assert_controllers_connected "cyvasse-match"
    click_on "Random Setup"
    assert_no_selector ".cyvasse-dock .dock-unit"
    # The opponent readying writes the match: a new version reaches the poll.
    travel(2.seconds) { @match.reload.touch }
    sleep 2.5 # two live polls land, one carrying the new version
    assert_no_selector ".cyvasse-dock .dock-unit"
    assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='1']", count: 19
  end

  test "a poll answered after the army is submitted never puts the old state back" do
    visit match_path(@match)
    assert_controllers_connected "cyvasse-match"
    click_on "Random Setup"
    # Hold each poll's answer so one is still in flight when the army goes in.
    page.execute_script(<<~JS)
      window.__loaded = []
      const board = Stimulus.getControllerForElementAndIdentifier(document.querySelector("#{BOARD}"), "cyvasse-match")
      const load = board.load.bind(board)
      board.load = (state, options) => { window.__loaded.push(Number(state.version)); return load(state, options) }
      const real = window.fetch
      window.fetch = (url, init) => init?.method === "POST" ? real(url, init) : real(url, init).then((answer) => new Promise((ok) => setTimeout(() => ok(answer), 1500)))
    JS
    sleep 1.2
    click_on "Ready"
    sleep 3
    loaded = page.evaluate_script("window.__loaded")
    assert_operator loaded.size, :>=, 1
    assert_equal loaded.sort, loaded, "the board only ever moves forward"
  end

  test "while the computer is to move, the player sees it thinking" do
    @match.set_up!(@arya, CyvasseRules::Bot.random_lineup(rng: Random.new(2)))
    @match.reload
    @match.update_columns(whos_turn: Match::AWAY, bot_due_at: 1.hour.from_now) unless @match.seat_to_move == :away
    visit match_path(@match)
    assert_selector ".live-clock.is-thinking [data-cyvasse-match-target=clockLabel]",
                    text: "#{@match.display_name_of(@match.away_user)} is thinking…"
  end

  test "[e2e] the player sees the computer select its unit before it moves, and a cavalry's second jump follow" do
    match = computer_double_jump
    first, second = match.bot_plan["steps"]
    match.update_columns(bot_due_at: 1.hour.from_now)
    visit match_path(match)
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: /is thinking/
    assert_no_selector "svg.cyvasse-board g.hex.is-selected"

    next_bot_step(match)
    assert_selector "#{hex(first.first)}.is-selected.has-unit[data-team='0']", wait: 5
    assert_no_selector "#{hex(first.last)}.has-unit"

    next_bot_step(match)
    assert_selector "#{hex(first.last)}.is-selected.has-unit[data-team='0']", wait: 5
    assert_no_selector "#{hex(first.first)}.has-unit"
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: /is thinking/

    next_bot_step(match)
    assert_selector "#{hex(second.last)}.has-unit[data-team='0']", wait: 5
    assert_no_selector "svg.cyvasse-board g.hex.is-selected"
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: /Your move/
  end

  test "[component] under reduced motion the computer's selection lands at once, with no ripple" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    begin
      match = computer_double_jump
      first = match.bot_plan["steps"].first
      match.update_columns(bot_due_at: 1.hour.from_now)
      visit match_path(match)
      next_bot_step(match)
      assert_selector "#{hex(first.first)}.is-selected", wait: 5
      ripple = page.evaluate_script(<<~JS)
        Stimulus.getControllerForElementAndIdentifier(document.querySelector("#{BOARD}"), "cyvasse-match").rippleTimer
      JS
      assert_nil ripple, "no ripple timer runs"
      assert_selector "svg.cyvasse-board g.hex.is-lit"
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end
  end
end
