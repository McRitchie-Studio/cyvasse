require "application_system_test_case"

# [e2e] The pencil skin's team rim (task cyvasse-pencil-team-rim). A pencil
# piece stands on a parchment disc that covers most of its hex, so the hex's
# team shade (blue yours, red theirs, game.css .unit-shade) showed only in the
# corners, and the orange of the last move, the selection and the danger pulse
# drowned even that: you could not tell whose piece was whose. Each pencil
# disc now draws its own thin rim in its team's colour, the same colour as the
# hex's team shade, and the orange glow rings outside it (.unit-ring), so the
# two read together. The vector skin draws no disc and is unchanged.
#
# Measured in pixels: the share of a band on the disc's upper rim (the side
# the art clip never cuts) that reads clearly blue, clearly red, or clearly
# orange. The team band sits on the disc's edge; the glow band just outside.
#
# PENCIL_RIM_SHOTS=<dir> saves pencil-rim-<label>-<state>-<theme>.png of the
# board (label from PENCIL_RIM_LABEL, default "after").
class PencilTeamRimTest < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze
  # Their catapult on 36, king on 1, elephant on 58, rabbles on 25 and 47;
  # your king on 91, elephant on 59 and rabbles on 70 and 57. Their rabble
  # on 47 stands next to your rabble on 57, which it can take next turn.
  POSITION = { "0-15" => 36, "0-17" => 1, "0-6" => 58, "0-1" => 25, "0-2" => 47,
               "1-17" => 91, "1-6" => 59, "1-1" => 70, "1-2" => 57 }.freeze
  BLUE = "(r, g, b) => b > 150 && b - r > 70 && b - g > 30"
  RED = "(r, g, b) => r > 150 && g < 100 && b < 100 && r - g > 90"
  ORANGE = "(r, g, b) => r > 170 && r - g > 30 && g - b > 40"

  setup do
    motion("reduce") # steady rings, so a pixel read sees a known frame
  end

  teardown do
    page.execute_script("try { localStorage.clear() } catch {}")
    motion("no-preference")
  end

  test "pencil: each disc carries its team's rim, blue yours and red theirs, alongside the orange rings" do
    visit play_path(skin: "pencil")
    start_game("pencil")
    # Their rabble has just moved 26 -> 25.
    stage(POSITION, last_move: [ 26, 25 ])
    mouse_away
    classic_scrollbars
    shots("last-move")

    # Unmarked: your rabble reads blue, their catapult red.
    assert_team 70, :blue
    assert_team 36, :red

    # The rim's colour is the team shade's own (the board's shade-<team>
    # gradient, cyvasse_game_controller TEAM_SHADE).
    { 70 => 1, 36 => 0 }.each do |hex, team|
      shade = page.evaluate_script("getComputedStyle(document.querySelector('#shade-#{team} stop')).stopColor")
      assert_equal shade, style("g.hex[data-hex='#{hex}'] .unit-disc")["stroke"], "hex #{hex}'s rim is team #{team}'s shade"
    end

    # Last moved: their rabble keeps its red rim, with the orange ring outside.
    assert_team 25, :red
    assert_operator band(25, :orange, :glow), :>, 0.35, "the last move still rings the disc in orange"

    # In danger: your rabble their rabble can take keeps its blue rim.
    assert_selector "svg.cyvasse-board g.hex.is-danger[data-hex='57']"
    assert_team 57, :blue
    shots("danger")

    # Selected: your rabble keeps its blue rim, with the orange ring outside.
    find("svg.cyvasse-board g.hex[data-hex='70']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='70']"
    mouse_away
    shots("selected")
    assert_team 70, :blue
    assert_operator band(70, :orange, :glow), :>, 0.35, "the selection still rings the disc in orange"
  end

  test "pencil: the board key's Your piece and Enemy piece swatches show the team rim" do
    visit play_path(skin: "pencil")
    start_game("pencil")
    find(".cyvasse-legend summary").click
    { "yours" => "rgb(59, 130, 246)", "enemy" => "rgb(220, 38, 38)" }.each do |key, colour|
      look = page.evaluate_script("(() => { const s = getComputedStyle(document.querySelector('.cyvasse-legend-swatch[data-swatch=#{key}] .cyvasse-legend-disc')); return [s.display, s.stroke] })()")
      assert_equal [ "inline", colour ], look, key
    end
  end

  test "vector: unchanged, no disc, no rim, no ring" do
    visit play_path(skin: "vector")
    start_game("vector")
    stage(POSITION, last_move: [ 26, 25 ])
    %w[70 25].each do |hex|
      disc = style("g.hex[data-hex='#{hex}'] .unit-disc")
      assert_equal [ "none", "none" ], disc.values_at("fill", "stroke"), hex
      assert_equal "none", style("g.hex[data-hex='#{hex}'] .unit-ring")["display"], hex
    end
    find(".cyvasse-legend summary").click
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.cyvasse-legend-swatch[data-swatch=yours] .cyvasse-legend-disc')).display")
  end

  private

  def assert_team(hex, colour)
    other = colour == :blue ? :red : :blue
    own = band(hex, colour, :team)
    theirs = band(hex, other, :team)
    assert_operator own, :>, 0.5, "hex #{hex}'s rim reads #{colour} (#{own} of the band)"
    assert_operator theirs, :<, 0.05, "hex #{hex}'s rim never reads #{other} (#{theirs})"
  end

  def start_game(skin)
    assert_selector "[data-controller=cyvasse-game][data-skin=#{skin}][data-phase=setup]"
    assert_controllers_connected("cyvasse-game", "cyvasse-openings")
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15
  end

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

  # The share of pixels reading `colour` in a band on the disc's upper rim
  # (from half past ten to half past one, the side no clip cuts): :team on
  # the disc's edge, :glow just outside it.
  def band(hex, colour, where)
    test_fn = { blue: BLUE, red: RED, orange: ORANGE }.fetch(colour)
    inner, outer = { team: [ -1.0, 0.6 ], glow: [ 2.0, 4.5 ] }.fetch(where)
    box = page.evaluate_script(<<~JS)
      (() => {
        const disc = document.querySelector("svg.cyvasse-board g.hex[data-hex='#{hex}'] .unit-disc")
        disc.scrollIntoView({ block: "center", inline: "center" })
        const r = disc.getBoundingClientRect()
        return { x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height }
      })()
    JS
    pad = 8
    clip = { x: box["x"] - pad, y: box["y"] - pad, width: box["width"] + 2 * pad, height: box["height"] + 2 * pad, scale: 1 }
    png = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", clip: clip)["data"]
    page.evaluate_async_script(<<~JS, png, pad, box["width"] / 2.0, inner, outer)
      const [png, pad, radius, inner, outer, done] = arguments;
      (async () => {
        const img = new Image(); img.src = "data:image/png;base64," + png; await img.decode();
        const c = document.createElement("canvas"); c.width = img.width; c.height = img.height;
        const ctx = c.getContext("2d"); ctx.drawImage(img, 0, 0);
        const data = ctx.getImageData(0, 0, img.width, img.height).data;
        const k = img.width / (radius * 2 + pad * 2);
        const cx = img.width / 2, cy = img.height / 2;
        const hit = #{test_fn};
        let band = 0, hits = 0;
        for (let py = 0; py < img.height; py++) for (let px = 0; px < img.width; px++) {
          const dx = (px + 0.5 - cx) / k, dy = (py + 0.5 - cy) / k;
          const d = Math.hypot(dx, dy) - radius;
          const angle = Math.atan2(-dy, dx) * 180 / Math.PI; // 0 = 3 o'clock, 90 = 12
          if (angle < 45 || angle > 135 || d < inner || d > outer) continue;
          band++;
          const i = (py * img.width + px) * 4;
          if (hit(data[i], data[i + 1], data[i + 2])) hits++;
        }
        done(band ? hits / band : 0);
      })().catch((e) => done(String(e)));
    JS
  end

  def style(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const s = getComputedStyle(document.querySelector("svg.cyvasse-board #{selector}"))
        return { display: s.display, fill: s.fill, stroke: s.stroke }
      })()
    JS
  end

  # CI's Linux Chrome draws classic scrollbars; draw them on every machine, so
  # a local run measures the layout CI does.
  def classic_scrollbars
    page.execute_script("const s = document.createElement('style'); s.textContent = '::-webkit-scrollbar { width: 15px; height: 15px; background: #888 } ::-webkit-scrollbar-thumb { background: #444 }'; document.head.append(s)")
  end

  def motion(value)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: value } ])
  end

  def mouse_away
    page.driver.browser.action.move_to_location(1, 1).perform
  end

  def shots(state)
    dir = ENV["PENCIL_RIM_SHOTS"] or return
    label = ENV.fetch("PENCIL_RIM_LABEL", "after")
    { "dark" => true, "light" => false }.each do |theme, dark|
      page.execute_script("document.documentElement.classList.#{dark ? 'add' : 'remove'}('dark')")
      sleep 0.3
      rect = page.evaluate_script("(() => { const r = document.querySelector('.cyvasse-board-wrap').getBoundingClientRect(); return { x: r.left, y: r.top + scrollY, width: r.width, height: r.height } })()")
      png = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", captureBeyondViewport: true,
                                             clip: rect.merge("scale" => 1))["data"]
      File.binwrite(File.join(dir, "pencil-rim-#{label}-#{state}-#{theme}.png"), Base64.decode64(png))
    end
    page.execute_script("document.documentElement.classList.add('dark')")
  end
end
