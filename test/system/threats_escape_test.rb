require "application_system_test_case"

# [component] The threat outline and "start over", in a real browser:
#
# - In play, the region the opponent could strike next turn is outlined, and
#   a unit of yours they could actually kill wears the danger ring; one that
#   is merely within reach does not. A switch turns it off and is remembered.
# - While a piece is picked, "Press Esc to start over" shows. Esc lets go of
#   the piece, puts back a picked dock unit in setup, and takes back a
#   cavalry unit's first jump (capture and all) before the turn is played.
class ThreatsEscapeTest < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze

  setup do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
  end

  test "setup: no threats, and Esc puts a picked dock unit back" do
    assert_no_selector ".cyvasse-threat-toggle", visible: true
    assert_equal "", outline
    first(".cyvasse-dock .dock-unit").click
    assert_selector "svg.cyvasse-board g.hex.is-drop", count: 40
    assert_selector ".cyvasse-hint", text: "Press Esc to start over"
    press_escape
    assert_no_selector "svg.cyvasse-board g.hex.is-drop"
    assert_no_selector ".cyvasse-hint", visible: true
  end

  test "the opponent's reach is outlined and only a killable unit is in danger" do
    start_game
    # A catapult (attack 3) in the middle of the board. On its row, an
    # elephant of yours (defence 4) stands in its line of fire and a rabble
    # of yours (defence 1) too: only the rabble can be killed.
    stage("0-15" => 46, "0-17" => 1, "1-17" => 91, "1-6" => 48, "1-1" => 44)
    screenshot("threats")

    assert_not_equal "", outline, "the outline is drawn"
    assert_selector "svg.cyvasse-board g.hex.is-threatened[data-hex='48']"
    assert_selector "svg.cyvasse-board g.hex.is-threatened[data-hex='44']"
    assert_no_selector "svg.cyvasse-board g.hex.is-threatened[data-hex='91']"
    assert_selector "svg.cyvasse-board g.hex.is-danger[data-hex='44'][aria-description^='In danger']"
    assert_no_selector "svg.cyvasse-board g.hex.is-danger[data-hex='48']"
    assert_no_selector "svg.cyvasse-board g.hex.is-danger[data-hex='91']"
    assert_equal [ "44" ], danger_hexes
    assert_equal "inline", page.evaluate_script("getComputedStyle(document.querySelector(\"g.hex[data-hex='44'] .danger-ring\")).display")

    # The outline runs round the region's outer edge only: a hex deep inside
    # the catapult's range (47, between it and the elephant) has no edge on it.
    edges = outline_segments
    centre = hex_centre(47)
    assert edges.none? { |(ax, ay), (bx, by)| (((ax + bx) / 2 - centre[0])**2 + ((ay + by) / 2 - centre[1])**2) < 40**2 },
      "no outline edge runs through the middle of the region"

    # Move the rabble out of range: the danger follows the position.
    stage("0-15" => 46, "0-17" => 1, "1-17" => 91, "1-6" => 48, "1-1" => 90)
    assert_equal [], danger_hexes

    # The switch hides it all, and the choice survives a reload.
    uncheck "Show threats"
    assert_equal "", outline
    assert_no_selector "svg.cyvasse-board g.hex.is-danger"
    visit play_path
    start_game
    assert_no_checked_field "Show threats"
    assert_equal "", outline
    check "Show threats"
    assert_not_equal "", outline
  end

  test "at the opening the outline draws no edge along the board's own rim" do
    start_game
    segments = outline_segments
    assert_not_empty segments, "the outline is drawn at the opening"

    # An edge between two board hexes has a hex centre half a hex (W / 2 = 30)
    # from its midpoint on each side; an edge on the rim has only one. The
    # outline marks where the reach ends inside the board, never the board's
    # own edge, so the opening board does not wear a frame.
    rim = segments.select { |edge| hexes_beside(edge) == 1 }
    assert_empty rim, "#{rim.size} of #{segments.size} outline edges lie on the board's rim"
    assert segments.all? { |edge| hexes_beside(edge) == 2 }, "every outline edge lies between two board hexes"
  end

  test "Esc lets go of a piece and takes back a cavalry unit's first jump" do
    start_game
    # A light horse of yours on 80 with an enemy rabble two hexes away.
    prey = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("cyvasse/board").then((board) => {
        done(board.HEXES.find((h) => board.distance(board.hexAt(80), h) === 2 && h.index < 80).index)
      })
    JS
    stage("1-8" => 80, "1-17" => 91, "0-17" => 1, "0-1" => prey)
    horse = find("svg.cyvasse-board g.hex[data-hex='80']")
    assert_equal "Your light horse", horse["aria-label"]

    horse.click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='80']"
    assert_selector ".cyvasse-hint", text: "Press Esc to start over"
    press_escape
    assert_no_selector "svg.cyvasse-board g.hex.is-selected"
    assert_no_selector ".cyvasse-hint", visible: true

    # The first jump captures the rabble; the horse must jump again.
    horse.click
    find("svg.cyvasse-board g.hex[data-hex='#{prey}']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='#{prey}']"
    assert_equal [ 2, "dead" ], page.evaluate_script("[#{CONTROLLER}.game.jump, #{CONTROLLER}.game.unit('0-1').status]")
    assert_selector ".cyvasse-hint", text: "Press Esc to start over"
    screenshot("second-jump")
    press_escape

    # Taken back: the horse home, the rabble standing, the turn still ours.
    assert_selector "svg.cyvasse-board g.hex[data-hex='80'][aria-label='Your light horse']"
    assert_selector "svg.cyvasse-board g.hex[data-hex='#{prey}'][aria-label='Enemy rabble']"
    assert_no_selector "svg.cyvasse-board g.hex.is-selected"
    assert_equal [ 1, 1, "alive" ], page.evaluate_script("[#{CONTROLLER}.game.jump, #{CONTROLLER}.game.offense, #{CONTROLLER}.game.unit('0-1').status]")
    # Any unit may move again, not just the horse.
    find("svg.cyvasse-board g.hex[data-hex='91']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='91']"
  end

  test "on a touch screen the hint is a Start over button" do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 5)
    page.current_window.resize_to(390, 844)
    visit play_path
    start_game
    assert page.evaluate_script("matchMedia('(hover: none) and (pointer: coarse)').matches"), "touch is emulated"
    stage("1-8" => 80, "1-17" => 91, "0-17" => 1, "0-15" => 46, "0-1" => 45)
    find("svg.cyvasse-board g.hex[data-hex='80']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='80']"
    assert_selector ".cyvasse-hint", text: "Start over"
    assert_no_text "Press Esc"
    page.execute_script("document.querySelector('.cyvasse-board-bar').scrollIntoView(); window.scrollBy(0, -130)")
    screenshot("phone")
    find(".cyvasse-hint").click
    assert_no_selector "svg.cyvasse-board g.hex.is-selected"
  ensure
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
    page.current_window.resize_to(1400, 1100)
  end

  private

  def start_game
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15
  end

  # Clear the board and stand only these units ({ unit id => hex }), with
  # the player to move.
  def stage(spots)
    page.execute_script(<<~JS, spots)
      const ctrl = #{CONTROLLER}
      for (const unit of ctrl.game.units) { unit.status = "dead"; unit.hex = null }
      for (const [id, hex] of Object.entries(arguments[0])) {
        const unit = ctrl.game.unit(id)
        unit.status = "alive"
        unit.hex = hex
      }
      ctrl.game.offense = 1
      ctrl.clearSelection()
      ctrl.render()
    JS
  end

  def press_escape
    find("body").send_keys(:escape)
  end

  def outline
    page.evaluate_script("document.querySelector('svg.cyvasse-board path.threat-outline').getAttribute('d') || ''")
  end

  def outline_segments
    outline.scan(/M([\d.]+) ([\d.]+)L([\d.]+) ([\d.]+)/).map { |a| a.map(&:to_f).each_slice(2).to_a }
  end

  # How many board hexes an outline edge lies against: 2 inside the board, 1 on its rim.
  def hexes_beside(((ax, ay), (bx, by)))
    @centres ||= page.evaluate_script("[...#{CONTROLLER}.hexCentres.values()].map((c) => [c.x, c.y])")
    mx = (ax + bx) / 2
    my = (ay + by) / 2
    @centres.count { |x, y| Math.hypot(x - mx, y - my) < 31 }
  end

  def hex_centre(hex)
    page.evaluate_script("(() => { const c = #{CONTROLLER}.hexCentres.get(#{hex}); return [c.x, c.y] })()")
  end

  def danger_hexes
    page.evaluate_script("[...document.querySelectorAll('g.hex.is-danger')].map((g) => g.dataset.hex)")
  end

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    sleep 0.4
    page.save_screenshot(Rails.root.join("tmp/screenshots/threats-#{name}.png"))
  end
end
