require "application_system_test_case"

# [e2e] Play layouts (task cyvasse-play-layout-fit). The setup layouts
# (setup_layout_fit_test, phone_setup_dock_test) keep the board on the screen
# while an army is placed; these keep it there for the game itself.
#
# - A phone on its side (844x390): once play starts the board sits beside
#   the sidebar, sized to the screen's height, and stays on the screen while
#   the sidebar scrolls. It once ran to about 630px in a 390px screen.
# - Short laptops (1280x800, 1133x744): the board is capped to the room left
#   under the page's top, so all of it is on the screen at once.
# - A phone held upright, on a match: no empty band between the versus card
#   and the board while no banner shows (it was about 100px).
# - A phone held upright, in a live match's setup: one clock on the screen,
#   the docked sheet's, not the timer card's peeking above it.
#
# "On the screen" means every one of the 91 hexes wholly inside the viewport
# and under the pinned navbar. PLAY_FIT_SHOTS=<dir> saves each case as
# play-fit-after-*.png.
class PlayLayoutFitTest < ApplicationSystemTestCase
  include MatchPlay

  SIZES = [
    [ "phone-landscape", 844, 390, true ],
    [ "laptop", 1280, 800, false ],
    [ "short-laptop", 1133, 744, false ]
  ].freeze

  teardown do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  SIZES.each do |label, width, height, touch|
    test "/play shows the whole board during play at #{width}x#{height}" do
      screen!(width, height, touch:)
      visit play_path
      assert_controllers_connected "cyvasse-game"
      assert_selector "svg.cyvasse-board g.hex", count: 91
      smart_setup!
      click_on "Ready"
      assert_selector ".cyvasse-game[data-phase=play]", wait: 10

      assert_whole_board "/play at #{width}x#{height}"
      assert_no_sideways_scroll
      shot("play-#{label}")
      assert_board_stays_as_the_page_scrolls("/play at #{width}x#{height}") if touch
    end

    test "a live match shows the whole board during play at #{width}x#{height}" do
      visit_live_match { screen!(width, height, touch:) }
      smart_setup!
      click_on "Ready"
      assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10

      assert_whole_board "a match at #{width}x#{height}"
      assert_no_sideways_scroll
      shot("match-#{label}")
      assert_board_stays_as_the_page_scrolls("a match at #{width}x#{height}") if touch
    end
  end

  test "a desktop of normal height keeps the full-size board" do
    screen!(1400, 1000, touch: false)
    visit play_path
    assert_selector "svg.cyvasse-board g.hex", count: 91
    assert_in_delta 704, find("svg.cyvasse-board").rect.width, 1, "the board keeps its full 44rem"
  end

  test "a phone match in play has no empty band above the board while no banner shows" do
    visit_live_match { screen!(390, 844, touch: true) }
    smart_setup!
    click_on "Ready"
    assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10
    assert_selector ".cyvasse-banner", visible: :hidden, wait: 10
    assert_no_selector ".cyvasse-hint", visible: :visible

    versus = rect(".match-versus-card")
    board = rect("svg.cyvasse-board")
    assert_operator board["top"] - versus["bottom"], :<=, 24, "the band between the versus card and the board"
    shot("match-phone-390x844")

    # The start-over hint rises over the gap, clear of the board.
    own = find("svg.cyvasse-board g.hex.has-unit[data-team='1']", match: :first)
    own.click
    assert_selector ".cyvasse-hint", visible: :visible
    hint = rect(".cyvasse-hint")
    assert_operator hint["bottom"], :<=, rect("svg.cyvasse-board")["top"] + 0.5, "the hint is not drawn over the board"
    assert_in_delta board["top"], rect("svg.cyvasse-board")["top"], 0.5, "the hint's coming moved the board"
    shot("match-phone-390x844-hint")
  end

  test "a phone match's setup shows one clock, the docked sheet's" do
    visit_live_match { screen!(390, 844, touch: true) }
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_selector ".cyvasse-army .cyvasse-army-clock", text: /\A\d+s\z/
    clocks = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".live-clock, .cyvasse-army-clock")].filter((node) => {
        const r = node.getBoundingClientRect()
        return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight
      }).map((node) => node.className)
    JS
    assert_equal [ "cyvasse-army-clock" ], clocks.map { _1.split.first }, "one setup clock on the screen"
    shot("match-phone-390x844-setup")

    # The timer card's clock is back once the sheet is gone.
    smart_setup!
    click_on "Ready"
    assert_selector "[data-controller=cyvasse-match][data-phase=play]", wait: 10
    assert_selector ".match-panel .live-clock", visible: :visible
  end

  private

  def screen!(width, height, touch:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height:, deviceScaleFactor: 1, mobile: touch)
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 5) if touch
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
                                    features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
  end

  def visit_live_match
    arya = make_player("arya")
    match = Match.start_live!(arya, computer: true, rng: Random.new(4))
    visit link_path(token: Studio::Link.create_magic_link(email: arya.email).token)
    assert_text "Signed in as arya"
    yield
    visit match_path(match)
    assert_controllers_connected "cyvasse-match"
  end

  # Waits up to four seconds for the board to settle whole on the screen (the
  # opening scroll and the navbar's collapse), then asserts it.
  def assert_whole_board(moment)
    box = nil
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 4
    loop do
      box = hexes_in_view
      break if box["outside"].empty? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
    assert_equal 91, box["total"]
    assert_empty box["outside"], "#{moment}: hexes off the screen #{box.except("outside").inspect}"
  end

  # The sidebar scrolls; the board stays.
  def assert_board_stays_as_the_page_scrolls(moment)
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    sleep 0.3
    assert_whole_board "#{moment}, scrolled to the page's foot"
  end

  def hexes_in_view
    page.evaluate_script(<<~JS)
      (() => {
        const pinned = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--pin-stack-bottom")) || 0
        const hexes = [...document.querySelectorAll("svg.cyvasse-board g.hex")]
        const outside = hexes.filter((hex) => {
          const r = hex.querySelector(".hex-poly").getBoundingClientRect()
          return r.top < pinned - 0.5 || r.bottom > innerHeight + 0.5 || r.left < -0.5 || r.right > innerWidth + 0.5
        }).map((hex) => hex.dataset.hex ?? hex.getAttribute("aria-label"))
        const b = document.querySelector("svg.cyvasse-board").getBoundingClientRect()
        return { total: hexes.length, outside, pinned, scrollY, viewport: [innerWidth, innerHeight],
                 board: [b.top, b.bottom, b.left, b.right].map(Math.round) }
      })()
    JS
  end

  def rect(selector)
    page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return { top: r.top, bottom: r.bottom } })()")
  end

  def assert_no_sideways_scroll
    scroll, client = page_widths
    assert_operator scroll, :<=, client, "no sideways scroll"
  end

  def shot(name)
    dir = ENV["PLAY_FIT_SHOTS"]
    return unless dir

    FileUtils.mkdir_p(dir)
    page.save_screenshot(File.join(dir, "play-fit-after-#{name}.png"))
  end
end
