require "application_system_test_case"

# [component] The threat outline and "start over", in a real browser:
#
# - In play, every hex the opponent could strike next turn is outlined, and
#   a unit of yours they could actually kill is marked in danger; one that
#   is merely within reach is not. (The look: board_highlights_test.rb.) A switch turns it off and is remembered.
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
    assert_equal 0, outline
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

    assert_operator outline, :>, 0, "the reach is outlined"
    assert_selector "svg.cyvasse-board g.hex.is-threatened[data-hex='48']"
    assert_selector "svg.cyvasse-board g.hex.is-threatened[data-hex='44']"
    assert_no_selector "svg.cyvasse-board g.hex.is-threatened[data-hex='91']"
    # VoiceOver hears the danger as part of the unit's name: its own label,
    # then the visually hidden note (Chrome's computed name, read over CDP).
    assert_equal "Your rabble In danger: the opponent can take it next turn", accessible_name("g.hex[data-hex='44']")
    assert_equal "Your elephant", accessible_name("g.hex[data-hex='48']")
    assert page.evaluate_script("document.getElementById('cyvasse-game-danger-note').hidden"),
      "the note is hidden, so browse mode never reads it on its own"
    assert_no_selector "svg.cyvasse-board g.hex.is-danger[data-hex='48']"
    assert_no_selector "svg.cyvasse-board g.hex.is-danger[data-hex='91']"
    assert_equal [ "44" ], danger_hexes

    # Move the rabble out of range: the danger follows the position.
    stage("0-15" => 46, "0-17" => 1, "1-17" => 91, "1-6" => 48, "1-1" => 90)
    assert_equal [], danger_hexes

    # The switch hides it all, and the choice survives a reload.
    uncheck "Show threats"
    assert_equal 0, outline
    assert_no_selector "svg.cyvasse-board g.hex.is-danger"
    visit play_path
    start_game
    assert_no_checked_field "Show threats"
    assert_equal 0, outline
    check "Show threats"
    assert_operator outline, :>, 0
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

  # How many hexes wear the opponent's-reach outline.
  def outline
    page.evaluate_script("document.querySelectorAll('svg.cyvasse-board g.hex.is-threatened').length")
  end

  # The name Chrome's accessibility tree computes for the element (what a
  # screen reader is handed), not the attribute the page set.
  def accessible_name(selector)
    browser = page.driver.browser
    root = browser.execute_cdp("DOM.getDocument", depth: 0)["root"]["nodeId"]
    node = browser.execute_cdp("DOM.querySelector", nodeId: root, selector: selector)["nodeId"]
    tree = browser.execute_cdp("Accessibility.getPartialAXTree", nodeId: node, fetchRelatives: false)
    tree["nodes"].first.dig("name", "value")
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
