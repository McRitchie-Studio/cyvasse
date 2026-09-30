require "application_system_test_case"

# [component] [e2e] The last move's mark (task cyvasse-last-move-fade): a soft
# orange glow over the hex a unit left and the hex it reached, fading away and
# cleared ten seconds after the move lands (cyvasse/last_move). It draws no
# edge, so a unit of the computer's that just moved into its own threat area
# wears no red ring of its own inside the threat outline.
class LastMoveFadeTest < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze
  # Alex's screenshot: their catapult, king and rabble; their elephant has just
  # moved 48 -> 58; your king, your elephant on 59 (in danger), your rabble.
  POSITION = { "0-15" => 36, "0-17" => 1, "0-6" => 58, "0-1" => 25, "1-17" => 91, "1-6" => 59, "1-1" => 70 }.freeze

  setup do
    motion("no-preference")
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
  end

  test "the last move glows soft orange, draws no ring, and is gone ten seconds after it lands" do
    start_game
    stage(POSITION, last_move: [ 48, 58 ])
    mouse_away
    screenshot("after")

    assert_selector "svg.cyvasse-board g.hex.is-last-move", count: 2
    [ 48, 58 ].each do |hex|
      glow = style("g.hex[data-hex='#{hex}'] .last-move-glow")
      assert_equal [ "inline", "cyvasse-last-move" ], glow.values_at("display", "animationName")
      assert_match(/url\("#last-move-glow"\)/, glow["fill"])
      assert_equal 'url("#hex-base")', style("g.hex[data-hex='#{hex}'] .hex-poly")["fill"], "no solid orange fill"
    end
    stops = page.evaluate_script("[...document.querySelectorAll('#last-move-glow stop')].map((s) => Number(s.getAttribute('stop-opacity')))")
    assert stops.all? { |o| o < 0.7 }, "a soft glow, not a solid fill: #{stops}"
    assert_equal 1.0, page.evaluate_script("Number(getComputedStyle(document.querySelector(\"g.hex[data-hex='58'] .unit-shade\")).opacity)"),
      "the moved unit keeps its team shade"

    # No edge round the moved elephant but the threat outline and your
    # endangered elephant's pulse; no team ring anywhere.
    kinds = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("svg.cyvasse-board line.hex-edge[data-kind]")].map((l) => [l.dataset.between, l.dataset.kind])
    JS
    assert_empty kinds.select { |_, kind| kind.start_with?("team-") || kind == "last-move" }
    round_58 = kinds.select { |between, _| between.split.include?("58") }
    assert round_58.all? { |between, kind| kind == "perimeter" || (kind == "danger" && between.split.include?("59")) }, round_58.inspect
    assert_selector "svg.cyvasse-board g.hex.is-danger[data-hex='59']"

    # A redraw partway through carries the fade on rather than restarting it.
    sleep 3
    page.execute_script("#{CONTROLLER}.render()")
    delay = page.evaluate_script("getComputedStyle(document.querySelector('svg.cyvasse-board')).getPropertyValue('--last-move-delay')").to_f
    assert_operator delay, :<=, -2500, "the fade's clock runs from the move, not the redraw"
    assert_selector "svg.cyvasse-board g.hex.is-last-move", count: 2

    # Gone by ten seconds after the move, and a redraw does not bring it back.
    assert_no_selector "svg.cyvasse-board g.hex.is-last-move", wait: 9
    page.execute_script("#{CONTROLLER}.render()")
    assert_no_selector "svg.cyvasse-board g.hex.is-last-move"
    screenshot("after-10s")
  ensure
    page.execute_script("try { localStorage.clear() } catch {}")
  end

  test "after a real move the mark shows, then clears after ten seconds" do
    start_game
    stage(POSITION)
    find("svg.cyvasse-board g.hex[data-hex='70']").click
    target = find("svg.cyvasse-board g.hex.is-move", match: :first)["data-hex"]
    find("svg.cyvasse-board g.hex[data-hex='#{target}']").click
    assert_selector "svg.cyvasse-board g.hex.is-last-move", minimum: 2
    moved_at = Time.now
    assert_selector "[data-controller=cyvasse-game][data-offense='1'][data-holding=false]", wait: 15
    assert_no_selector "svg.cyvasse-board g.hex.is-last-move", wait: 14
    assert_operator Time.now - moved_at, :>=, 5, "it lasted, rather than clearing at once"
  ensure
    page.execute_script("try { localStorage.clear() } catch {}")
  end

  test "less motion: a steady glow, no fade animation, still cleared at ten seconds" do
    motion("reduce")
    start_game
    stage(POSITION, last_move: [ 48, 58 ])
    glow = style("g.hex[data-hex='48'] .last-move-glow")
    assert_equal [ "inline", "none" ], glow.values_at("display", "animationName")
    assert_in_delta 0.6, glow["opacity"].to_f, 0.01
    assert_no_selector "svg.cyvasse-board g.hex.is-last-move", wait: 12
  ensure
    motion("no-preference")
    page.execute_script("try { localStorage.clear() } catch {}")
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

  # Clear the board and stand only these units ({ unit id => hex }), the
  # player to move, with `last_move` as the move just played.
  def stage(spots, last_move: [])
    page.execute_script(<<~JS, spots, last_move)
      const ctrl = #{CONTROLLER}
      for (const unit of ctrl.game.units) { unit.status = "dead"; unit.hex = null }
      for (const [id, hex] of Object.entries(arguments[0])) {
        const unit = ctrl.game.unit(id)
        unit.status = "alive"
        unit.hex = hex
      }
      ctrl.game.offense = 1
      ctrl.game.lastMove = arguments[1]
      ctrl.game.utilMove = null
      ctrl.clearSelection()
      ctrl.render()
    JS
  end

  def motion(value)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: value } ])
  end

  def mouse_away
    page.driver.browser.action.move_to_location(1, 1).perform
  end

  def style(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const s = getComputedStyle(document.querySelector("svg.cyvasse-board #{selector}"))
        return { display: s.display, animationName: s.animationName, fill: s.fill, stroke: s.stroke, opacity: s.opacity }
      })()
    JS
  end

  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    sleep 0.4
    page.save_screenshot(ENV.fetch("SCREENSHOT_DIR", Rails.root.join("tmp/screenshots").to_s) + "/last-move-#{name}#{ENV['SKIN_SUFFIX']}.png")
  end
end
