require "application_system_test_case"

# [component] The board's resting look and the "Your army" setup panel, in a
# real browser:
#
# - Every plain hex is a cool slate gradient (#hex-base), not flat black.
# - Your five setup rows are near-black with a subtle gradient and the hatch
#   (#hex-deploy), darker than the plain board; once a unit is picked, the
#   empty hexes it may go to light up (#hex-drop).
# - "Ready" is the panel's main call to action: a filled violet button,
#   disabled and muted until every unit is on the board. "Random Setup" is a
#   hollow outline button.
class SetupLookTest < ApplicationSystemTestCase
  test "the setup rows are dark and textured, the board slate, and Ready waits for a full army" do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
    screenshot("empty")

    assert_selector "svg.cyvasse-board defs radialGradient#hex-base", visible: :all
    assert_selector "svg.cyvasse-board defs radialGradient#hex-deploy", visible: :all
    # The computer's rows and the middle row are the plain slate board.
    assert_equal [ 'url("#hex-base")' ], fills("g.hex:not(.is-deploy)")
    # Your rows are the dark deploy gradient, hatched.
    assert_equal 40, all("svg.cyvasse-board g.hex.is-deploy").size
    assert_equal [ 'url("#hex-deploy")' ], fills("g.hex.is-deploy")
    assert_equal [ "inline" ], textures("g.hex.is-deploy")
    assert_equal [ "none" ], textures("g.hex:not(.is-deploy)")
    # The deploy gradient is darker than the plain board's.
    assert_operator luminance("hex-deploy"), :<, luminance("hex-base")

    # Ready is there from the start, but disabled and muted.
    ready = find_button("Ready", disabled: true)
    assert_operator ready.style("opacity")["opacity"].to_f, :<, 0.6
    random = find_button("Random Setup")
    assert_includes random[:class], "btn-outline"
    assert_equal "rgba(0, 0, 0, 0)", random.style("background-color")["background-color"]

    # Picking a unit lights the empty hexes it may go to.
    first(".cyvasse-dock .dock-unit").click
    assert_selector "svg.cyvasse-board g.hex.is-drop", count: 40
    assert_equal [ 'url("#hex-drop")' ], fills("g.hex.is-drop")
    assert_operator luminance("hex-drop"), :>, luminance("hex-base")
    screenshot("pick")
    find("svg.cyvasse-board g.hex[data-hex='56']").click
    assert_selector "svg.cyvasse-board g.hex[data-hex='56'].has-unit"
    assert_no_selector "svg.cyvasse-board g.hex.is-drop"
    assert_button "Ready", disabled: true

    # A full army enables Ready: a solid violet fill at full strength.
    click_on "Random Setup"
    ready = find_button("Ready")
    sleep 0.4 # the button eases out of its muted state
    assert_equal "1", ready.style("opacity")["opacity"]
    r, g, b = ready.style("background-color")["background-color"].scan(/\d+/).map(&:to_i)
    assert_operator b, :>, g + 60, "violet: blue well above green"
    assert_operator r, :>, g + 30, "violet: red above green"
    screenshot("ready")
    within(".skin-toggle") { click_on "Pencil" }
    assert_selector "[data-controller=cyvasse-game][data-skin=pencil]"
    screenshot("ready-pencil")
    page.execute_script("document.documentElement.classList.remove('dark')")
    assert_equal [ 'url("#hex-deploy")' ], fills("g.hex.is-deploy")
    screenshot("ready-pencil-light")
    page.execute_script("document.documentElement.classList.add('dark')")

    # In play the whole board is the slate gradient again.
    click_on "Ready"
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    assert_no_selector "svg.cyvasse-board g.hex.is-deploy"
    assert_equal [ 'url("#hex-base")' ], fills("g.hex:not(.is-last-move):not(.is-selected)")
  end

  private

  def fills(selector)
    sleep 0.4 # the hex fill eases over 0.25 s
    page.evaluate_script("[...document.querySelectorAll(#{"svg.cyvasse-board #{selector} .hex-poly".to_json})].map((p) => getComputedStyle(p).fill)").uniq
  end

  def textures(selector)
    page.evaluate_script("[...document.querySelectorAll(#{"svg.cyvasse-board #{selector} .ring-texture".to_json})].map((p) => getComputedStyle(p).display)").uniq
  end

  # The mean relative lightness of a gradient's stops, weighted by opacity.
  def luminance(id)
    page.evaluate_script(<<~JS)
      (() => {
        const stops = [...document.querySelectorAll("##{id} stop")]
        const probe = document.createElement("div")
        document.body.append(probe)
        const values = stops.map((stop) => {
          probe.style.color = stop.getAttribute("stop-color")
          const [r, g, b] = getComputedStyle(probe).color.match(/\\d+(\\.\\d+)?/g).map(Number)
          return (0.2126 * r + 0.7152 * g + 0.0722 * b) * parseFloat(stop.getAttribute("stop-opacity") ?? "1")
        })
        probe.remove()
        return values.reduce((a, b) => a + b, 0) / values.length
      })()
    JS
  end

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    page.save_screenshot(Rails.root.join("tmp/screenshots/setup-#{name}.png"))
  end
end
