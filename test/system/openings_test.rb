require "application_system_test_case"

# [e2e] The opening picker and the value shading in a real browser: a visitor
# loads one of the twenty openings (app/javascript/cyvasse/openings.js) onto
# the board, and each unit's hex is shaded by what the piece is worth.
class OpeningsSystemTest < ApplicationSystemTestCase
  test "load an opening during setup against the computer; each hex is shaded by the worth of its piece" do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
    assert_selector ".cyvasse-dock .dock-unit", count: 19

    select "Crown Forward", from: "Opening"
    assert_text "near enough the middle to move first"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }

    assert_text "Loaded Crown Forward."
    assert_no_selector ".cyvasse-dock .dock-unit"
    # Crown Forward: the king on the second row's middle hex (66), the
    # trebuchet and catapult on the front row above it (56, 57). The shade
    # ranks mountain 0, then KILL_PRIORITY: trebuchet 7, catapult 8,
    # king 10.
    assert_selector "g.hex[data-hex='66'][data-unit-id='1-17'][data-rank='10'] .unit-shade[fill='url(#shade-1-10)']"
    assert_selector "g.hex[data-hex='56'][data-unit-id='1-14'][data-rank='7']"
    assert_selector "g.hex[data-hex='57'][data-unit-id='1-15'][data-rank='8']"
    assert_selector "g.hex[data-rank='0'] .unit-shade[fill='url(#shade-1-0)']", count: 2
    assert_selector "g.hex[data-rank]", count: 19
    screenshot("crown-forward")

    # Picking the king up again marks it selected; its heavy shade gives way
    # so the orange shows.
    find("g.hex[data-hex='66']").click
    assert_selector "g.hex[data-hex='66'].is-selected"
    assert_operator shade_opacity(66), :<, 0.5
    assert_operator shade_opacity(56), :==, 1.0
    find("g.hex[data-hex='66']").click

    # The cues let the orange and red through by thinning the shade.
    mark(56, "is-last-move")
    assert_operator shade_opacity(56), :<, 0.3
    mark(56, "is-attack")
    assert_operator shade_opacity(56), :<, 0.3
    unmark(56)
    assert_operator shade_opacity(56), :==, 1.0

    # The last move keeps a team mark whatever the unit is worth: a rabble
    # (rank 1, the faintest shade) on hex 79 gets a blue edge.
    assert_selector "g.hex[data-hex='79'][data-rank='1'][data-team='1']"
    mark(79, "is-last-move")
    assert_edge 79, "rgb(59, 130, 246)"
    screenshot("last-move-rabble")
    unmark(79)
    assert_edge 79, "rgb(255, 255, 255)"

    click_on "Start Game"
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    assert_selector "g.hex[data-rank]", count: 38
    assert_selector "g.hex[data-team='0'][data-rank='10'] .unit-shade[fill='url(#shade-0-10)']"
    enemy_rabble = find("g.hex.has-unit[data-team='0'][data-rank='1']", match: :first)["data-hex"].to_i
    mark(enemy_rabble, "is-last-move")
    assert_edge enemy_rabble, "rgb(220, 38, 38)"
    screenshot("last-move-enemy-rabble")
    unmark(enemy_rabble)
    screenshot("play")
  end

  private

  # Put a play-phase cue class on a hex directly: the rule under test is the
  # stylesheet's, and a real last move or attack depends on the computer's
  # dice.
  def mark(hex, cue)
    page.execute_script("const g = document.querySelector(\"g.hex[data-hex='#{hex}']\"); g.classList.remove('is-last-move', 'is-attack'); g.classList.add('#{cue}')")
  end

  def unmark(hex)
    page.execute_script("document.querySelector(\"g.hex[data-hex='#{hex}']\").classList.remove('is-last-move', 'is-attack')")
  end

  # The hex edge settles on `colour` (the edge fades over 0.25s), four wide
  # for a team mark.
  def assert_edge(hex, colour)
    script = "getComputedStyle(document.querySelector(\"g.hex[data-hex='#{hex}'] .hex-poly\")).stroke"
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    seen = page.evaluate_script(script)
    while seen != colour && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.05
      seen = page.evaluate_script(script)
    end
    assert_equal colour, seen, "hex #{hex} edge"
    width = page.evaluate_script(script.sub(".stroke", ".strokeWidth")).to_f
    assert_equal(colour == "rgb(255, 255, 255)" ? 1.5 : 4.0, width, "hex #{hex} edge width")
  end

  def shade_opacity(hex)
    page.evaluate_script("parseFloat(getComputedStyle(document.querySelector(\"g.hex[data-hex='#{hex}'] .unit-shade\")).opacity)")
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/openings-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
