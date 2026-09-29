require "application_system_test_case"

# [e2e] The board for a screen reader, and its key, on /play (task
# cyvasse-board-legend-accessibility):
#
# - Each hex's aria-label names what stands on it, or its index when empty.
# - With a unit of yours picked, a legal move reads "move here", a legal
#   attack "Attack enemy ...", anywhere else "unreachable"; the picked hex is
#   aria-pressed, and the status line (the board's one live region) says what
#   was picked. Letting go puts every label back.
# - Keyboard play is as before: arrows move, Enter picks and lets go.
# - The board key opens beside the threat switches, one entry per look.
class BoardLabelsTest < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze

  # A rabble of yours on 75, an enemy rabble beside it on 66, a mountain of
  # yours on 76, the kings far off.
  SPOTS = { "1-1" => 75, "0-1" => 66, "1-17" => 91, "0-17" => 1, "1-18" => 76 }.freeze

  setup do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
  end

  test "hex labels name the occupant, then what a click does while a unit is picked" do
    start_game
    stage(SPOTS)

    assert_equal "Your rabble", label(75)
    assert_equal "Enemy rabble", label(66)
    assert_equal "Mountain", label(76)
    assert_equal "Your king", label(91)
    assert_equal "Hex 46", label(46)
    assert_no_selector "svg.cyvasse-board g.hex[aria-pressed]"

    moves, attacks = page.evaluate_script("(() => { const a = #{CONTROLLER}.game.actionsFrom(75); return [a.moves, a.attacks] })()")
    assert_includes attacks, 66, "the staged rabble can take its neighbour"
    move = moves.first
    far = page.evaluate_script("[...Array(40).keys()].map((i) => i + 2).find((i) => !#{moves}.includes(i) && !#{CONTROLLER}.game.pieceAt(i))")

    hex(75).click
    assert_selector "svg.cyvasse-board g.hex[data-hex='75'][aria-pressed=true]"
    assert_selector "svg.cyvasse-board g.hex[aria-pressed]", count: 1
    assert_equal "Your rabble, selected", label(75)
    assert_equal "Hex #{move}, move here", label(move)
    assert_equal "Attack enemy rabble", label(66)
    assert_equal "Hex #{far}, unreachable", label(far)
    assert_equal "Mountain, unreachable", label(76)
    assert_equal "Your king", label(91), "another unit of yours stays as it is"
    assert_match(/Rabble selected: \d+ moves?, 1 attack\./, status_text)
    assert_equal 1, page.evaluate_script("document.querySelectorAll('.cyvasse-game [aria-live]').length"),
      "the status line stays the one live region"

    hex(75).click
    assert_no_selector "svg.cyvasse-board g.hex[aria-pressed]"
    assert_equal "Your rabble", label(75)
    assert_equal "Hex #{move}", label(move)
    assert_equal "Enemy rabble", label(66)
    assert_no_match(/selected/, status_text)
  end

  test "keyboard play: arrows move, Enter picks and lets go, and the labels follow" do
    start_game
    stage(SPOTS)
    page.execute_script("#{CONTROLLER}.focusHex(74)")
    active.send_keys(:arrow_right)
    assert_equal "75", page.evaluate_script("document.activeElement.dataset.hex")
    active.send_keys(:enter)
    assert_selector "svg.cyvasse-board g.hex[data-hex='75'][aria-pressed=true][aria-label='Your rabble, selected']"
    assert_match(/Rabble selected/, status_text)
    active.send_keys(:enter)
    assert_no_selector "svg.cyvasse-board g.hex[aria-pressed]"
    assert_equal "Your rabble", label(75)
  end

  test "the board key opens beside the threat switches" do
    assert_no_selector ".cyvasse-legend", visible: true
    start_game
    stage(SPOTS)
    assert_selector ".cyvasse-board-bar .cyvasse-legend", visible: true
    assert_no_selector ".cyvasse-legend-panel", visible: true
    hex(75).click
    find(".cyvasse-legend summary").click
    assert_selector ".cyvasse-legend-entry", count: BoardLegendHelper::BOARD_LEGEND.size, visible: true
    assert_selector ".cyvasse-legend-entry", text: "Move here"
    assert_selector "svg.cyvasse-board g.hex[data-hex='75'][aria-pressed=true]", "reading the key keeps the pick"
    screenshot("desktop")
    find(".cyvasse-legend summary").click
    assert_no_selector ".cyvasse-legend-panel", visible: true
  end

  test "on a phone the key is a small ? that opens over the board" do
    page.current_window.resize_to(390, 844)
    visit play_path
    start_game
    stage(SPOTS)
    summary = find(".cyvasse-legend summary")
    assert_operator summary.native.size.width, :<, 40, "only the ? shows"
    summary.click
    panel = find(".cyvasse-legend-panel")
    rect = page.evaluate_script("(() => { const r = document.querySelector('.cyvasse-legend-panel').getBoundingClientRect(); return [r.left, r.right] })()")
    assert_operator rect[0], :>=, 0, "the panel stays on screen"
    assert_operator rect[1], :<=, page.evaluate_script("document.documentElement.clientWidth")
    assert panel.visible?
    screenshot("phone")
  end

  private

  def start_game
    assert_controllers_connected("cyvasse-game")
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15
  end

  # Clear the board and stand only these units ({ unit id => hex }), with
  # the player to move (as threats_escape_test.rb stages).
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
      ctrl.game.lastMove = []
      ctrl.game.utilMove = null
      ctrl.clearSelection()
      ctrl.render()
    JS
  end

  def hex(index)
    find("svg.cyvasse-board g.hex[data-hex='#{index}']")
  end

  def label(index)
    hex(index)["aria-label"]
  end

  def status_text
    find("[data-cyvasse-game-target=status]").text
  end

  def active
    page.driver.browser.switch_to.active_element
  end

  def screenshot(name)
    dir = ENV["SCREENSHOTS"]
    return unless dir

    sleep 0.4
    page.save_screenshot(File.join(dir, "board-legend-#{name}.png"))
  end
end
