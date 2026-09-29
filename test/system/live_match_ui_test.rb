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

  test "[e2e] the header puts an avatar at each edge, the computer's piece art on the right, and fits a phone" do
    visit match_path(@match)
    them = @match.display_name_of(@match.away_user)
    assert_selector "h1.match-versus [data-side=me] [data-avatar=piece] img[src*='pieces/vector/']"
    assert_selector "h1.match-versus [data-side=them] [data-avatar=bot-fallback][aria-label='#{them}'] img[src*='pieces/vector/']"
    assert_selector "h1.match-versus [data-side=them]", text: them
    me, vs, bot = %w[[data-side=me]\ [data-avatar] .match-versus-vs [data-side=them]\ [data-avatar]].map do |css|
      page.evaluate_script("document.querySelector('h1.match-versus #{css}').getBoundingClientRect().left")
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

  test "a poll answered after the army is submitted never puts the old state back" do
    visit match_path(@match)
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

  # Select our units in turn until one has somewhere to go, and take the
  # first move offered (a cavalry unit then jumps again).
  def take_a_turn
    all("svg.cyvasse-board g.hex.has-unit[data-team='1']").map { |node| node["data-hex"] }.each do |hex|
      find("svg.cyvasse-board g.hex[data-hex='#{hex}']").click
      target = first("svg.cyvasse-board g.hex.is-attack, svg.cyvasse-board g.hex.is-move", minimum: 0, wait: 0)
      next unless target

      target.click
      if page.has_selector?("[role=status]", text: "jumps again", wait: 0.3)
        first("svg.cyvasse-board g.hex.is-attack, svg.cyvasse-board g.hex.is-move").click
      end
      return
    end
    flunk "none of our units could move"
  end

  test "[e2e] the player dismisses the warning, takes back the seat, and moves again" do
    @match.set_up!(@arya, CyvasseRules::Bot.random_lineup(rng: Random.new(2)))
    # The computer is to move and thinks until the test says otherwise.
    @match.reload.update_columns(whos_turn: Match::AWAY, bot_due_at: 1.hour.from_now, home_strikes: 1, updated_at: Time.current)
    visit match_path(@match)

    assert_text "You missed a clock"
    find("[data-cyvasse-match-target=noticeDismiss]").click
    assert_no_text "You missed a clock"

    @match.update_columns(home_bot: true, home_strikes: 2, updated_at: Time.current)
    assert_text "a computer player has taken your seat", wait: 5
    assert_no_selector "[data-cyvasse-match-target=noticeDismiss]", visible: true
    page.save_screenshot(Rails.root.join("tmp/screenshots/take-back-seat.png")) if ENV["SCREENSHOTS"]
    click_on "Take back my seat"
    assert_text "You took back your seat"
    page.save_screenshot(Rails.root.join("tmp/screenshots/took-back-seat.png")) if ENV["SCREENSHOTS"]
    assert_no_selector "[data-match-slot=take-back-seat]", visible: true
    assert_not @match.reload.bot_seat?(:home)

    # The computer's move lands (as a poll would settle it): the turn is hers.
    @match.update_columns(whos_turn: Match::HOME, bot_due_at: nil, clock_started_at: Time.current, updated_at: Time.current)
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: /Your move|Hurry/, wait: 5
    turn = @match.reload.turn
    take_a_turn
    assert_selector "[data-cyvasse-match-target=clockLabel]", text: /is thinking/, wait: 5
    assert_operator @match.reload.turn, :>, turn
    assert_equal 2, @match.home_strikes
  end
end
