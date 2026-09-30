require "application_system_test_case"

# [e2e] The pencil skin's glow (task cyvasse-pencil-glow-visibility). The
# pencil piece stands on a parchment disc that covers most of its hex, so the
# hex's soft centre glow (game.css .hex-glow) showed only as faint orange
# corners on a moved or selected piece, and read grey-brown over a blue
# team's rim. In the pencil skin the glow also rings the disc: an orange rim
# with a soft halo, fading with the last move and pulsing with the selection.
# The vector skin draws no disc and keeps the hex glow alone.
#
# Measured in pixels: orange pixels in a band just outside the disc's upper
# rim (the side the art clip never cuts), on the marked hex against the same
# kind of piece unmarked. Since task cyvasse-pencil-team-rim the disc's own
# edge is its team's colour and the orange ring (.unit-ring) draws just
# outside it, so the band sits outside the disc and the ring's animation is
# read off .unit-ring.
#
# PENCIL_GLOW_SHOTS=<dir> saves pencil-glow-<label>-<theme>.png of the board
# (label from PENCIL_GLOW_LABEL, default "after").
class PencilGlowTest < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze
  # Their catapult on 36, king on 1, elephant on 58 and rabble on 25; your
  # king on 91, elephant on 59 and rabble on 70. The rim is measured on the
  # small rabbles, whose discs sit well inside their hexes, clear of any
  # orange highlight edge (the selection's, the danger pulse's).
  POSITION = { "0-15" => 36, "0-17" => 1, "0-6" => 58, "0-1" => 25, "1-17" => 91, "1-6" => 59, "1-1" => 70 }.freeze
  # A clearly orange pixel: warm, red well over green, green well over blue.
  ORANGE = "(r, g, b) => r > 170 && r - g > 30 && g - b > 40"

  setup do
    motion("no-preference")
  end

  teardown do
    page.execute_script("try { localStorage.clear() } catch {}")
  end

  test "pencil: the last move and the selection ring the disc in orange; the last move's ring fades" do
    visit play_path(skin: "pencil")
    start_game("pencil")
    # Their rabble has just moved 26 -> 25.
    stage(POSITION, last_move: [ 26, 25 ])
    mouse_away
    classic_scrollbars
    freeze_last_move_at(0)
    shots("last-move")

    moved = rim_orange(25)
    plain = rim_orange(70)
    assert_operator plain, :<, 0.05, "an unmarked piece's rim is plain parchment: #{plain}"
    assert_operator moved, :>, 0.35, "the moved piece's rim glows orange (#{moved} of the band, unmarked #{plain})"

    assert_equal "cyvasse-last-move-rim", style("g.hex[data-hex='25'] .unit-ring")["animationName"]
    assert_equal "none", style("g.hex[data-hex='70'] .unit-ring")["display"], "an unmarked disc draws no orange ring"

    # The ring fades with the hex glow: near the end of its ten seconds, most
    # of the orange is gone.
    freeze_last_move_at(9_000)
    late = rim_orange(25)
    assert_operator late, :<, moved / 2.0, "the ring fades (#{moved} at the start, #{late} at nine seconds)"

    # Selecting your rabble (a blue piece) rings its disc, and the pulse
    # never lets the ring go: at its faintest it is still clearly orange.
    find("svg.cyvasse-board g.hex[data-hex='70']").click
    assert_selector "svg.cyvasse-board g.hex.is-selected[data-hex='70']"
    mouse_away
    freeze_selection_at(0)
    shots("selected")
    assert_equal "cyvasse-selected-rim", style("g.hex[data-hex='70'] .unit-ring")["animationName"]
    freeze_selection_at(900) # the pulse's faintest point, half way through
    faint = rim_orange(70)
    assert_operator rim_orange(25), :<, 0.05, "their rabble, no longer the last move, is plain again"
    assert_operator faint, :>, 0.3, "the selected blue piece's rim is orange even at the pulse's faintest (#{faint})"

    # For the eye only: a large piece (your elephant), its ring cut with its
    # disc along the tile's right and lower sides.
    if ENV["PENCIL_GLOW_SHOTS"]
      find("body").send_keys(:escape)
      find("svg.cyvasse-board g.hex[data-hex='59']").click
      mouse_away
      freeze_selection_at(0)
      shots("selected-large")
      stage(POSITION, last_move: [ 48, 58 ])
      mouse_away
      freeze_last_move_at(0)
      shots("last-move-large")
    end
  end

  test "pencil: a redraw partway through carries the ring's fade on, counting the time run once" do
    visit play_path(skin: "pencil")
    start_game("pencil")
    stage(POSITION, last_move: [ 26, 25 ])
    sleep 3
    page.execute_script("#{CONTROLLER}.render()")
    progress = page.evaluate_script(<<~JS)
      document.querySelector("svg.cyvasse-board g.hex[data-hex='25'] .unit-ring").getAnimations()
        .find((a) => a.animationName === "cyvasse-last-move-rim").effect.getComputedTiming().progress
    JS
    assert_operator progress, :>, 0.2, "the ring's fade runs from the move, not the redraw"
    assert_operator progress, :<, 0.45, "a redraw must not jump the ring's fade ahead"
  end

  test "pencil, less motion: the rings are steady, the last move's fainter" do
    motion("reduce")
    visit play_path(skin: "pencil")
    start_game("pencil")
    stage(POSITION, last_move: [ 26, 25 ])
    disc = style("g.hex[data-hex='25'] .unit-ring")
    assert_equal "none", disc["animationName"]
    assert_in_delta 0.6, disc["strokeOpacity"].to_f, 0.01
    find("svg.cyvasse-board g.hex[data-hex='70']").click
    disc = style("g.hex[data-hex='70'] .unit-ring")
    assert_equal [ "none", "1" ], disc.values_at("animationName", "strokeOpacity")
  ensure
    motion("no-preference")
  end

  test "pencil: the board key's Selected and Last move swatches show the ringed disc" do
    visit play_path(skin: "pencil")
    start_game("pencil")
    find(".cyvasse-legend summary").click
    %w[selected last-move].each do |key|
      look = page.evaluate_script("(() => { const s = getComputedStyle(document.querySelector('.cyvasse-legend-swatch[data-swatch=#{key}] .cyvasse-legend-disc')); return [s.display, s.stroke] })()")
      assert_equal [ "inline", "rgb(255, 154, 31)" ], look, key
    end
  end

  test "vector: unchanged, the hex glow alone and no disc ring" do
    visit play_path(skin: "vector")
    start_game("vector")
    stage(POSITION, last_move: [ 48, 58 ])
    glow = style("g.hex[data-hex='58'] .hex-glow")
    assert_equal [ "inline", "cyvasse-last-move" ], glow.values_at("display", "animationName")
    disc = style("g.hex[data-hex='58'] .unit-disc")
    assert_equal [ "none", "none", "none" ], disc.values_at("fill", "stroke", "animationName")
    assert_equal "none", style("g.hex[data-hex='58'] .unit-ring")["display"]
    find("svg.cyvasse-board g.hex[data-hex='59']").click
    assert_equal [ "none", "none" ], style("g.hex[data-hex='59'] .unit-disc").values_at("stroke", "animationName")
    assert_equal "none", style("g.hex[data-hex='59'] .unit-ring")["display"]
    find(".cyvasse-legend summary").click
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.cyvasse-legend-swatch[data-swatch=selected] .cyvasse-legend-disc')).display")
  end

  private

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

  # Pause every animation of that name at a point in its run, so a pixel read
  # sees a known frame.
  def freeze(prefix, ms)
    page.execute_script(<<~JS, prefix, ms)
      for (const a of document.getAnimations()) {
        if (a.animationName?.startsWith(arguments[0])) { a.pause(); a.currentTime = arguments[1] }
      }
    JS
    sleep 0.15
  end

  def freeze_last_move_at(ms) = freeze("cyvasse-last-move", ms)
  def freeze_selection_at(ms) = freeze("cyvasse-selected", ms)

  # The share of pixels in a band just outside the disc's upper rim (from
  # half past ten to half past one, the side no clip cuts), clear of its team
  # rim, that read clearly orange.
  def rim_orange(hex)
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
    # Within the viewport: capturing beyond it resizes the page, and with
    # classic scrollbars (CI's Linux Chrome) the board then shifts under the
    # rect just read.
    png = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", clip: clip)["data"]
    page.evaluate_async_script(<<~JS, png, pad, box["width"] / 2.0)
      const [png, pad, radius, done] = arguments;
      (async () => {
        const img = new Image(); img.src = "data:image/png;base64," + png; await img.decode();
        const c = document.createElement("canvas"); c.width = img.width; c.height = img.height;
        const ctx = c.getContext("2d"); ctx.drawImage(img, 0, 0);
        const data = ctx.getImageData(0, 0, img.width, img.height).data;
        const k = img.width / (radius * 2 + pad * 2);
        const cx = img.width / 2, cy = img.height / 2;
        const orange = #{ORANGE};
        let band = 0, hits = 0;
        for (let py = 0; py < img.height; py++) for (let px = 0; px < img.width; px++) {
          const dx = (px + 0.5 - cx) / k, dy = (py + 0.5 - cy) / k;
          const d = Math.hypot(dx, dy);
          const angle = Math.atan2(-dy, dx) * 180 / Math.PI; // 0 = 3 o'clock, 90 = 12
          if (angle < 45 || angle > 135 || d - radius < 2 || d - radius > 4.5) continue;
          band++;
          const i = (py * img.width + px) * 4;
          if (orange(data[i], data[i + 1], data[i + 2])) hits++;
        }
        done(band ? hits / band : 0);
      })().catch((e) => done(String(e)));
    JS
  end

  def style(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const s = getComputedStyle(document.querySelector("svg.cyvasse-board #{selector}"))
        return { display: s.display, animationName: s.animationName, fill: s.fill, stroke: s.stroke,
                 strokeOpacity: s.strokeOpacity, opacity: s.opacity, filter: s.filter }
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
    dir = ENV["PENCIL_GLOW_SHOTS"] or return
    label = ENV.fetch("PENCIL_GLOW_LABEL", "after")
    { "dark" => true, "light" => false }.each do |theme, dark|
      page.execute_script("document.documentElement.classList.#{dark ? 'add' : 'remove'}('dark')")
      sleep 0.3
      rect = page.evaluate_script("(() => { const r = document.querySelector('.cyvasse-board-wrap').getBoundingClientRect(); return { x: r.left, y: r.top + scrollY, width: r.width, height: r.height } })()")
      png = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", captureBeyondViewport: true,
                                             clip: rect.merge("scale" => 1))["data"]
      File.binwrite(File.join(dir, "pencil-glow-#{label}-#{state}-#{theme}.png"), Base64.decode64(png))
    end
    page.execute_script("document.documentElement.classList.add('dark')")
  end
end
