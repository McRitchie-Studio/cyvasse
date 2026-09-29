require "application_system_test_case"

# [component] The ring ripple's look in a real browser: when a unit is picked
# in play, its move and attack hexes are painted with the gradients the
# controller defines once in the board's <defs> (lighter at the centre, deeper
# at the edge, one per ring code and ripple step), a fine hatch texture lies
# over every lit hex, and the selected hex keeps its flat orange.
class RangeGradientTest < ApplicationSystemTestCase
  ORANGE = "rgb(255, 165, 0)".freeze

  test "a selected dragon's range is painted with ring gradients and a texture, and the selection stays orange" do
    visit play_path
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15

    screenshot("before-select")
    dragon = find("svg.cyvasse-board g.hex[aria-label='Your dragon']")
    hex = dragon["data-hex"]
    dragon.click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='#{hex}']"
    assert_selector "svg.cyvasse-board g.hex.is-move", minimum: 3

    # The gradients and the texture pattern are defined once, in <defs>.
    assert_selector "svg.cyvasse-board defs radialGradient[id^='ring-']", visible: :all, minimum: 8
    assert_selector "svg.cyvasse-board defs pattern#ring-texture", visible: :all

    # Every move hex is filled from a ring gradient, not a bare hsl() colour,
    # and carries the texture overlay, shown.
    fills = settled { page.evaluate_script(<<~JS) }
      [...document.querySelectorAll("g.hex.is-move")].map((g) => [
        getComputedStyle(g.querySelector(".hex-poly")).fill,
        g.classList.contains("is-lit"),
        getComputedStyle(g.querySelector(".ring-texture")).display,
        g.querySelector(".ring-texture").getAttribute("fill")
      ])
    JS
    fills.each do |fill, lit, display, texture|
      assert_match(/\Aurl\("#ring-\d+-(short|long)-\d+"\)\z/, fill)
      assert lit, "a move hex is marked lit"
      assert_equal "inline", display
      assert_equal "url(#ring-texture)", texture
    end
    # The ripple keeps its outward brightening: more than one step is painted.
    steps = fills.map { |fill, *| fill[/-(\d+)"\)\z/, 1] }.uniq
    assert_operator steps.size, :>, 1, "the ripple spans several steps"

    # The selected hex keeps its flat orange and is not textured.
    assert_equal ORANGE, fill_of(hex)
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(\"g.hex[data-hex='#{hex}'] .ring-texture\")).display")
    # An unlit hex keeps the slate board gradient and no hatch.
    dark = page.evaluate_script("[...document.querySelectorAll('g.hex:not(.is-lit):not(.is-selected):not(.is-move):not(.is-attack) .hex-poly')].map((p) => getComputedStyle(p).fill)").uniq
    assert_equal [ %(url("#hex-base")) ], dark
    screenshot("dragon")

    # The pencil skin redraws only the art: the gradients stay on the rings.
    lit = lit_hexes
    within(".skin-toggle") { click_on "Pencil" }
    assert_selector "[data-controller=cyvasse-game][data-skin=pencil]"
    assert_equal lit, lit_hexes
    assert_match(/\Aurl\("#ring-/, fill_of(lit.first))
    screenshot("dragon-pencil")
    # The light site theme leaves the board's own colours alone.
    page.execute_script("document.documentElement.classList.remove('dark')")
    assert_match(/\Aurl\("#ring-/, fill_of(lit.first))
    assert_equal ORANGE, fill_of(hex)
    screenshot("dragon-pencil-light")
    page.execute_script("document.documentElement.classList.add('dark')")
    within(".skin-toggle") { click_on "Vector" }
    assert_selector "[data-controller=cyvasse-game][data-skin=vector]"

    # Picking another unit clears the dragon's gradients and texture from every
    # hex the new unit does not reach.
    before = lit_hexes
    king = find("svg.cyvasse-board g.hex[aria-label='Your king']")
    king_hex = king["data-hex"]
    king.click
    assert_no_selector "svg.cyvasse-board g.hex.is-selected[data-hex='#{hex}']"
    left = before - settled { lit_hexes } - [ king_hex ]
    assert_operator left.size, :>, 3
    left.each do |index|
      assert_equal %(url("#hex-base")), fill_of(index), "hex #{index} is back to the slate board"
      assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector(\"g.hex[data-hex='#{index}'] .ring-texture\")).display")
    end
    screenshot("king")
  end

  private

  def lit_hexes
    page.evaluate_script("[...document.querySelectorAll('g.hex.is-lit')].map((g) => g.dataset.hex)")
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

    page.save_screenshot(Rails.root.join("tmp/screenshots/gradient-#{name}.png"))
  end
end
