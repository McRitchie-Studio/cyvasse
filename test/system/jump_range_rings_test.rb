require "application_system_test_case"

# [component] The two ring kinds that sit beside the move gradients, in a real
# browser:
#
# - A cavalry unit's second-jump preview (move ring codes 6x/7x/8x) is a
#   "ghost": a faint gradient in the colour family of the live ring it previews
#   (move blue, capture red, blocked purple), rim-weighted, with a dashed edge
#   and no hatch, so it never reads as "move here now".
# - A shooter's range (rangeRings) is a zone: the line of fire (1x) is a soft
#   red field wash with the hatch, a hittable enemy (2x) a strong crimson
#   target, and a mountain in the line (4x) or its shadow (3x) a dim slate with
#   a dashed edge. A legal move inside the range keeps its move blue.
#
# Every fill is a gradient the controller builds once in the board's <defs>,
# one per ripple step, and the selected hex stays flat orange.
class JumpRangeRingsTest < ApplicationSystemTestCase
  ORANGE = "rgb(255, 165, 0)".freeze
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze

  setup do
    visit play_path
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15
  end

  test "a cavalry unit's second-jump preview is a ghost gradient with a dashed edge" do
    # Crown Forward: light horse on 52 and 61, heavy horse on 63 and 65.
    horse = find("svg.cyvasse-board g.hex[data-hex='61']")
    assert_equal "Your light horse", horse["aria-label"]
    horse.click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='61']"
    assert_selector "svg.cyvasse-board defs radialGradient[id^='ghost-']", visible: :all, minimum: 3

    cells = settled { ring_cells("rings") }
    screenshot("cavalry")
    ghosts = cells.select { |c| [ 6, 7, 8 ].include?(c["code"]) }
    assert_operator ghosts.size, :>=, 3, "the light horse previews a second jump"
    ghosts.each do |c|
      assert_match(/\Aurl\("#ghost-(240|10|280)-(short|long)-\d+"\)\z/, c["fill"], "hex #{c['hex']} code #{c['code']}")
      hue = { 6 => 240, 7 => 10, 8 => 280 }.fetch(c["code"])
      assert_includes c["fill"], "#ghost-#{hue}-"
      assert_not_equal "none", c["dash"], "hex #{c['hex']} has a dashed edge"
      assert c["ghost"], "hex #{c['hex']} is marked a ghost"
      assert_not c["lit"], "a ghost carries no hatch"
      assert_equal "none", c["texture"]
    end
    # The preview ripples outward too: more than one step is painted.
    assert_operator ghosts.map { |c| c["fill"][/-(\d+)"\)\z/, 1] }.uniq.size, :>, 1

    # The live move ring is still the solid, hatched gradient, with a solid edge.
    live = cells.select { |c| c["code"] == 1 }
    assert_operator live.size, :>=, 3
    live.each do |c|
      assert_match(/\Aurl\("#ring-240-/, c["fill"])
      assert_equal "none", c["dash"]
      assert c["lit"]
    end
    assert_equal ORANGE, fill_of(61)

    within(".skin-toggle") { click_on "Pencil" }
    assert_selector "[data-controller=cyvasse-game][data-skin=pencil]"
    assert_match(/\Aurl\("#ghost-/, fill_of(ghosts.first["hex"]))
    screenshot("cavalry-pencil")
    page.execute_script("document.documentElement.classList.remove('dark')")
    assert_match(/\Aurl\("#ghost-/, fill_of(ghosts.first["hex"]))
    assert_equal ORANGE, fill_of(61)
    screenshot("cavalry-pencil-light")
  end

  test "a shooter's range is a field wash with strong targets and dim blocked hexes" do
    # Stage a line of fire in the empty middle row: a mountain one hex ahead of
    # the trebuchet on 56 (throwing a shadow), and an enemy rabble two hexes
    # ahead on the other side, which a trebuchet (attack 1) can hit.
    staged = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      Promise.all([import("cyvasse/board"), import("cyvasse/rules")]).then(([board, rules]) => {
        const ctrl = #{CONTROLLER}
        const game = ctrl.game
        const origin = board.hexAt(56)
        const middle = board.HEXES.filter((h) => h.index >= 41 && h.index <= 51 && !game.pieceAt(h.index))
        const mountainHex = middle.find((h) => board.distance(origin, h) === 1 && rules.inARow(origin, h))
        const targetHex = middle.find((h) => board.distance(origin, h) === 2 && board.distance(mountainHex, h) >= 2)
        const mountain = game.teamUnits(1, "alive").find((u) => u.type.codename === "mountain")
        const rabble = game.teamUnits(0, "alive").find((u) => u.type.codename === "rabble")
        mountain.hex = mountainHex.index
        rabble.hex = targetHex.index
        ctrl.render()
        done([mountainHex.index, targetHex.index])
      })
    JS
    mountain_hex, target_hex = staged

    trebuchet = find("svg.cyvasse-board g.hex[data-hex='56']")
    assert_equal "Your trebuchet", trebuchet["aria-label"]
    trebuchet.click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='56']"
    %w[field target blocked].each do |kind|
      assert_selector "svg.cyvasse-board defs radialGradient[id^='#{kind}-']", visible: :all, minimum: 6
    end

    cells = settled { ring_cells("rangeRings") }
    screenshot("trebuchet")
    by_code = cells.group_by { |c| c["code"] }
    assert by_code[1]&.any?, "the line of fire is drawn"
    assert by_code[2]&.any?, "the staged rabble is a target"
    assert by_code[4]&.any?, "the staged mountain is in the line of fire"
    assert by_code[3]&.any?, "the mountain throws a shadow"
    assert_includes by_code[2].map { |c| c["hex"] }, target_hex
    assert_includes by_code[4].map { |c| c["hex"] }, mountain_hex

    by_code[1].each do |c|
      assert_match(/\Aurl\("#field-(short|long)-\d+"\)\z/, c["fill"], "hex #{c['hex']}")
      assert c["lit"], "the field carries the hatch"
      assert_equal "inline", c["texture"]
      assert_equal "none", c["dash"]
    end
    by_code[2].each do |c|
      assert_match(/\Aurl\("#target-(short|long)-\d+"\)\z/, c["fill"], "hex #{c['hex']}")
      assert c["classes"].include?("is-target")
    end
    (by_code[3] + by_code[4]).each do |c|
      assert_match(/\Aurl\("#blocked-(short|long)-\d+"\)\z/, c["fill"], "hex #{c['hex']}")
      assert_not_equal "none", c["dash"], "hex #{c['hex']} has a dashed edge"
      assert_not c["lit"], "a blocked hex carries no hatch"
    end
    # The field still ripples outward, step by step.
    assert_operator by_code[1].map { |c| c["fill"][/-(\d+)"\)\z/, 1] }.uniq.size, :>, 1
    # The target's edge is red and heavier than the field's.
    target = by_code[2].first
    assert_operator target["width"], :>, by_code[1].first["width"]
    assert_equal ORANGE, fill_of(56)

    within(".skin-toggle") { click_on "Pencil" }
    assert_selector "[data-controller=cyvasse-game][data-skin=pencil]"
    assert_match(/\Aurl\("#target-/, fill_of(target_hex))
    screenshot("trebuchet-pencil")
    page.execute_script("document.documentElement.classList.remove('dark')")
    assert_match(/\Aurl\("#field-/, fill_of(by_code[1].first["hex"]))
    screenshot("trebuchet-pencil-light")
    page.execute_script("document.documentElement.classList.add('dark')")
    within(".skin-toggle") { click_on "Vector" }
    assert_selector "[data-controller=cyvasse-game][data-skin=vector]"

    # A catapult moves as well as shoots: its legal moves keep the move blue
    # inside the range field, and the trebuchet's range is cleared.
    find("svg.cyvasse-board g.hex[data-hex='57']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='57']"
    moves = settled { page.evaluate_script("#{CONTROLLER}.actions.moves") }
    assert_operator moves.size, :>=, 1
    moves.each { |index| assert_match(/\Aurl\("#ring-240-/, fill_of(index), "move hex #{index}") }
    cells = ring_cells("rangeRings")
    assert cells.any? { |c| c["code"] == 1 && c["fill"].start_with?('url("#field-') }
    screenshot("catapult")
  end

  private

  # One row per ringed hex of the selected unit (the selection itself left
  # out): its ring code and how its hex is drawn.
  def ring_cells(map)
    page.evaluate_script(<<~JS)
      [...#{CONTROLLER}.actions.#{map}].filter(([, ring]) => ring >= 10).map(([hex, ring]) => {
        const g = document.querySelector(`g.hex[data-hex='${hex}']`)
        const poly = getComputedStyle(g.querySelector(".hex-poly"))
        return {
          hex, code: Math.floor(ring / 10), fill: poly.fill, dash: poly.strokeDasharray,
          width: parseFloat(poly.strokeWidth), classes: [...g.classList],
          lit: g.classList.contains("is-lit"), ghost: g.classList.contains("is-ghost"),
          texture: getComputedStyle(g.querySelector(".ring-texture")).display
        }
      })
    JS
  end

  def fill_of(hex)
    settled { page.evaluate_script("getComputedStyle(document.querySelector(\"g.hex[data-hex='#{hex}'] .hex-poly\")).fill") }
  end

  # The hex fill eases over 0.25 s; read once it has settled.
  def settled
    sleep 0.4
    yield
  end

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    page.save_screenshot(Rails.root.join("tmp/screenshots/rings-#{name}.png"))
  end
end
