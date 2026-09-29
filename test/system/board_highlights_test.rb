require "application_system_test_case"

# [component] [e2e] The threat highlights, in a real browser:
#
# - A unit of yours the opponent could kill next turn pulses orange from its
#   hex's edges (steady for a player who asked for less motion); no ring.
# - Every hex within the opponent's reach wears a full red outline, all six
#   edges, deep inside the region as well as at its rim.
class BoardHighlightsTest < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze
  RED = "rgb(239, 68, 68)".freeze
  WHITE = "rgb(255, 255, 255)".freeze

  setup do
    # Motion allowed, whatever an earlier test in this browser emulated.
    motion("no-preference")
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
  end

  test "a killable unit pulses orange from its hex edges, not a ring" do
    start_game
    # A catapult on 46; a rabble of yours (44) it can kill, an elephant (48) it cannot.
    stage("0-15" => 46, "0-17" => 1, "1-17" => 91, "1-6" => 48, "1-1" => 44)
    screenshot("staged")

    assert_no_selector "svg.cyvasse-board .danger-ring", visible: :all
    assert_selector "svg.cyvasse-board g.hex.is-danger[data-hex='44'] polygon.danger-edge"
    edge = style("g.hex[data-hex='44'] .danger-edge")
    assert_equal "inline", edge["display"]
    assert_equal "cyvasse-danger", edge["animationName"]
    assert_match(/url\("#danger-edge"\)/, edge["fill"])
    assert_equal "none", style("g.hex[data-hex='48'] .danger-edge")["display"], "within reach but not killable: no pulse"

    # The pulse breathes by opacity alone: no frame rebuilds geometry.
    frames = page.evaluate_script(<<~JS)
      [...document.styleSheets].flatMap((sheet) => { try { return [...sheet.cssRules] } catch { return [] } })
        .filter((rule) => rule.type === CSSRule.KEYFRAMES_RULE && rule.name === "cyvasse-danger")
        .flatMap((rule) => [...rule.cssRules].map((frame) => frame.style.cssText))
    JS
    assert_not_empty frames
    assert frames.all? { |frame| frame.match?(/\Aopacity: [\d.]+;\z/) }, "only opacity animates: #{frames}"

    # Less motion: a steady orange edge.
    motion("reduce")
    still = style("g.hex[data-hex='44'] .danger-edge")
    assert_equal "none", still["animationName"]
    assert_equal "inline", still["display"]
  ensure
    motion("no-preference")
  end

  test "every hex in the opponent's reach wears a full red outline" do
    start_game
    mouse_away
    screenshot("opening")
    assert_no_selector "svg.cyvasse-board path.threat-outline", visible: :all

    threatened = page.evaluate_script("[...document.querySelectorAll('g.hex.is-threatened')].map((g) => g.dataset.hex)")
    assert_not_empty threatened
    outlines = page.evaluate_script(<<~JS)
      [...document.querySelectorAll('g.hex.is-threatened:not(.is-last-move) .range-edge')].map((p) => {
        const s = getComputedStyle(p)
        return [s.display, s.stroke, s.strokeDasharray, parseFloat(s.strokeWidth), p.points.length]
      })
    JS
    assert outlines.all? { |display, stroke, dash, width, corners| display == "inline" && stroke == RED && dash == "none" && width >= 2 && corners == 6 },
      "every threatened hex has a solid red six-edge outline: #{outlines.uniq}"
    calm = page.evaluate_script("[...document.querySelectorAll('g.hex:not(.is-threatened):not(.is-last-move)')].map((g) => [getComputedStyle(g.querySelector('.hex-poly')).stroke, getComputedStyle(g.querySelector('.range-edge')).display])")
    assert_equal [ [ WHITE, "none" ] ], calm.uniq, "hexes out of reach keep their white edge"

    # Deep inside the reach, too: the catapult's line of fire from 46 runs
    # through 47 to 48, and 47 (between two threatened hexes) is outlined.
    stage("0-15" => 46, "0-17" => 1, "1-17" => 91, "1-6" => 48, "1-1" => 44)
    %w[47 48 44].each do |hex|
      assert_selector "svg.cyvasse-board g.hex.is-threatened[data-hex='#{hex}']"
      assert_equal [ "inline", RED ], style("g.hex[data-hex='#{hex}'] .range-edge").values_at("display", "stroke")
    end

    # The outline lies beneath the selection and the rings it lights: those
    # hexes drop the red edge and read clean; the rest of the reach keeps it.
    find("svg.cyvasse-board g.hex[data-hex='44']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='44']"
    mouse_away
    screenshot("selected")
    selected = style("g.hex[data-hex='44'] .hex-poly")
    assert_equal "rgb(255, 165, 0)", selected["fill"]
    lit = page.evaluate_script(<<~JS)
      [...document.querySelectorAll('g.hex.is-threatened')]
        .filter((g) => ['is-selected', 'is-move', 'is-attack', 'is-lit'].some((c) => g.classList.contains(c)))
        .map((g) => getComputedStyle(g.querySelector('.range-edge')).display)
    JS
    assert_includes lit, "none", "the selected rabble is threatened and lit"
    assert_equal [ "none" ], lit.uniq, "no lit hex wears the outline"
    assert_equal "inline", style("g.hex[data-hex='47'] .range-edge")["display"], "47 is not lit by the rabble, so it keeps its outline"

    # The last move's team edge reads over the outline too.
    find("body").send_keys(:escape)
    page.execute_script("const ctrl = #{CONTROLLER}; ctrl.game.lastMove = [43, 44]; ctrl.render()")
    assert_selector "svg.cyvasse-board g.hex.is-last-move", count: 2
    assert_equal "rgb(59, 130, 246)", style("g.hex[data-hex='44'] .hex-poly")["stroke"]
    assert_equal "none", style("g.hex[data-hex='44'] .range-edge")["display"]
  end

  private

  def start_game
    # Colours read at once, not partway through the edge's 0.25s fade.
    page.execute_script("document.head.insertAdjacentHTML('beforeend', '<style>.cyvasse-board .hex-poly { transition: none !important }</style>')")
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15
  end

  # Clear the board and stand only these units ({ unit id => hex }), the player to move.
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

  def motion(value)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: value } ])
  end

  # Off the board, so no hex wears the hover edge.
  def mouse_away
    page.driver.browser.action.move_to_location(1, 1).perform
  end

  def style(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const s = getComputedStyle(document.querySelector("svg.cyvasse-board #{selector}"))
        return { display: s.display, animationName: s.animationName, fill: s.fill, stroke: s.stroke }
      })()
    JS
  end

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    sleep 0.4
    page.save_screenshot(Rails.root.join("tmp/screenshots/highlights-#{name}.png"))
  end
end
