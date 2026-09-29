require "application_system_test_case"

# [component] [e2e] The threat highlights, in a real browser:
#
# - A unit of yours the opponent could kill next turn pulses orange from its
#   hex's edges (steady for a player who asked for less motion); no ring.
# - Only the rim of the opponent's reach is outlined red; edges inside it are
#   not. Each highlight edge is drawn once, full width, by its owner
#   (cyvasse/edges EDGE_PRIORITY), so a shared edge is never two colours.
class BoardHighlightsTest < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze
  RED = "rgb(239, 68, 68)".freeze
  WHITE = "rgb(255, 255, 255)".freeze
  ORANGE = "rgb(255, 165, 0)".freeze
  BLUE = "rgb(59, 130, 246)".freeze

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
    # Its edge is the danger orange, whole, and breathes with the glow.
    line = style("line.hex-edge[data-kind='danger'][data-between~='44']")
    assert_equal [ "rgb(249, 115, 22)", "cyvasse-danger" ], line.values_at("stroke", "animationName")

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
    assert_equal "none", style("line.hex-edge[data-kind='danger'][data-between~='44']")["animationName"]
  ensure
    motion("no-preference")
  end

  test "only the rim of the opponent's reach is outlined, each edge whole and in one colour" do
    start_game
    # A catapult on 46; a rabble of yours (44) it can kill, an elephant (48) it cannot.
    stage("0-15" => 46, "0-17" => 1, "1-17" => 91, "1-6" => 48, "1-1" => 44)
    mouse_away
    screenshot("perimeter")
    assert_no_selector "svg.cyvasse-board .range-edge", visible: :all

    # The area: every hex in reach, the opponent's own units counted in.
    edges = edge_table
    region = page.evaluate_script(<<~JS).to_set
      [...document.querySelectorAll("g.hex.is-threatened, g.hex.has-unit[data-team='0']")].map((g) => Number(g.dataset.hex))
    JS
    assert_operator region.size, :>, 10
    inside = ->(edge) { edge["between"].count { |hex| region.include?(hex) } }
    rim = edges.select { |e| inside.(e) == 1 }
    interior = edges.select { |e| inside.(e) == 2 }
    assert_not_empty interior
    # Every edge round the area is red unless a higher highlight owns it;
    # no edge inside it or off it is.
    perimeter = edges.select { |e| e["kind"] == "perimeter" }
    assert_not_empty perimeter
    assert perimeter.all? { |e| inside.(e) == 1 }, "a perimeter edge has the area on one side only"
    assert_equal rim.reject { |e| e["kind"] }.size, 0, "no edge round the area is left undrawn"
    assert_equal [ [ "inline", RED ] ], perimeter.map { |e| e.values_at("display", "stroke") }.uniq
    assert rim.any? { |e| e["between"].include?("rim") }, "the board's edge counts as outside"
    # Inside the area, edges between two plain hexes stay undrawn.
    plain = interior.select { |e| e["kind"].nil? }
    assert_not_empty plain
    assert_equal [ "none" ], plain.map { |e| e["display"] }.uniq
    # The hex's own edge stays thin and white: no hex wears a full outline.
    polys = page.evaluate_script("[...document.querySelectorAll('g.hex.is-threatened:not(.is-danger) .hex-poly')].map((p) => [getComputedStyle(p).stroke, getComputedStyle(p).strokeWidth])")
    assert_equal [ [ WHITE, "1.5px" ] ], polys.uniq

    # Full width: each drawn edge sits on the line two hexes share and is
    # wide enough to cover both hexes' own edges (0.97 scale, 1.5 wide).
    full = page.evaluate_script(<<~JS)
      (() => {
        const line = document.querySelector("svg.cyvasse-board line.hex-edge[data-kind='perimeter']")
        const [a, b] = line.dataset.between.split(" ")
        const centre = (hex) => document.querySelector(`g.hex[data-hex='${hex}']`).transform.baseVal[0].matrix
        const mx = (line.x1.baseVal.value + line.x2.baseVal.value) / 2, my = (line.y1.baseVal.value + line.y2.baseVal.value) / 2
        const ca = centre(a), gap = Math.hypot(mx - ca.e, my - ca.f)
        return { gap, width: parseFloat(getComputedStyle(line).strokeWidth), other: b === "rim" ? null : (() => { const cb = centre(b); return Math.hypot(mx - cb.e, my - cb.f) })() }
      })()
    JS
    band = full["gap"] * (1 - 0.97) + 0.75 # half the hex edge
    assert_operator full["width"] / 2, :>=, band, "the edge covers its hex's own edge"
    assert_in_delta full["gap"], full["other"], 0.05, "the line is on the shared edge" if full["other"]

    # The selection and its rings sit above the perimeter: edges they own are
    # not red, and the rest of the rim stays red.
    find("svg.cyvasse-board g.hex[data-hex='44']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='44']"
    mouse_away
    screenshot("perimeter-selected")
    edges = edge_table
    assert edges.select { |e| e["between"].include?(44) }.all? { |e| e["kind"] == "selected" && e["stroke"] == ORANGE }
    lit = page.evaluate_script("[...document.querySelectorAll('g.hex.is-move, g.hex.is-attack, g.hex.is-lit')].map((g) => Number(g.dataset.hex))")
    assert_not_empty lit
    assert_empty edges.select { |e| e["kind"] == "perimeter" && (e["between"] & lit).any? }, "the perimeter never crosses a ring"
    assert edges.any? { |e| e["kind"] == "perimeter" }

    # The last move beside a unit of yours just moved (the elephant, not in
    # danger, so its team edge shows): their shared edge is
    # the last move's orange, whole; the unit keeps its team edge elsewhere.
    find("body").send_keys(:escape)
    page.execute_script("const ctrl = #{CONTROLLER}; ctrl.game.lastMove = [47, 48]; ctrl.render()")
    assert_selector "svg.cyvasse-board g.hex.is-last-move", count: 2
    mouse_away
    screenshot("last-move-team")
    edges = edge_table
    shared = edges.find { |e| (e["between"] & [ 47, 48 ]).size == 2 }
    assert_equal [ "last-move", ORANGE, "inline" ], shared.values_at("kind", "stroke", "display")
    assert_equal 1, edges.count { |e| (e["between"] & [ 47, 48 ]).size == 2 }, "one line for the shared edge"
    own = edges.select { |e| e["between"].include?(48) } - [ shared ]
    assert own.any? { |e| e["kind"] == "team-1" && e["stroke"] == BLUE }, "the moved unit keeps its blue edge"
    assert_equal [ WHITE ], page.evaluate_script("[47, 48].map((h) => getComputedStyle(document.querySelector(`g.hex[data-hex='${h}'] .hex-poly`)).stroke)").uniq,
      "no half-width team stroke under the shared edge"

    # The keyboard's focus edge is drawn over every border.
    page.execute_script("arguments[0].focus()", find("g.hex[data-hex='45']"))
    find("g.hex[data-hex='45']").send_keys(:arrow_left)
    assert_equal "44", page.evaluate_script("document.activeElement.dataset.hex")
    cursor = page.evaluate_script(<<~JS)
      (() => {
        const c = document.querySelector("svg.cyvasse-board .hex-cursor.is-focus")
        const s = getComputedStyle(c)
        return [s.display, s.stroke, c.getAttribute("transform"), c === c.parentNode.lastElementChild]
      })()
    JS
    assert_equal [ "inline", "rgb(255, 255, 0)", find("g.hex[data-hex='44']")["transform"], true ], cursor

    # Show threats off: no perimeter at all.
    uncheck "Show threats"
    assert_empty edge_table.select { |e| e["kind"] == "perimeter" }
  ensure
    page.execute_script("try { localStorage.removeItem('cyvasse.showThreats') } catch {}")
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

  # Every edge line: the hexes it separates ("rim" off the board), its owner
  # and how it is drawn.
  def edge_table
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll("svg.cyvasse-board line.hex-edge")].map((l) => {
        const s = getComputedStyle(l)
        return { between: l.dataset.between.split(" ").map((h) => h === "rim" ? "rim" : Number(h)), kind: l.dataset.kind ?? null, display: s.display, stroke: s.stroke }
      })
    JS
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
