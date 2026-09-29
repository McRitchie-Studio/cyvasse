require "application_system_test_case"

# Captures the front door's background gallery (HomeGallery): one action shot
# per piece, each a real board state on /play staged so that piece is the hero.
#
# Not a test: the file name does not end in _test.rb, so no suite picks it up.
# Run it with
#
#   bin/rails cyvasse:capture_home_gallery          # every piece
#   PIECES=dragon,king bin/rails cyvasse:capture_home_gallery
#
# and it rewrites app/assets/images/backgrounds/home/<slug>.webp (a wide crop,
# 1800 px) and <slug>-mobile.webp (a portrait crop, 720 px). It needs cwebp
# (`brew install webp`). PREVIEW=1 also saves the whole board of each scene
# to tmp/home_gallery/<slug>-board.png.
#
# Deterministic: every scene below names every unit on the board and its hex,
# whose move it is and the last move; nothing is random. The board is drawn
# by the app's own controller (cyvasse_game_controller.js) in the default
# vector skin, dark theme, threats on and reduced motion (so the danger edge
# holds still), and the hero is selected the way a click selects it, so its
# rings are the game's own. A light horse's scene plays its first jump through
# the controller, so the picture is the second-jump board.
class HomeGalleryCapture < ApplicationSystemTestCase
  CONTROLLER = "Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=cyvasse-game]'), 'cyvasse-game')".freeze
  OUT = Rails.root.join("app/assets/images", HomeGallery::DIRECTORY)
  PREVIEWS = Rails.root.join("tmp/home_gallery")

  # Crops, in board units (a hex is 60 wide). The board is 668 x 597, a
  # hexagon, so a crop centred far from the middle catches the empty corners:
  # `reach` keeps each crop's centre that close to the board's centre, and the
  # hero may sit off the crop's centre instead.
  DESKTOP = { width: 440, height: 275, pixels: 1800, reach: { x: 60, y: 120 } }.freeze
  MOBILE = { width: 300, height: 480, pixels: 720, reach: { x: 134, y: 120 } }.freeze
  QUALITY = 72
  MAX_BYTES = 150 * 1024

  # [team, codename, hex]: team 1 is the player (blue, bottom rows 52-91),
  # team 0 the opponent (red, top rows 1-40); row 6 (41-51) is no man's land.
  # `select` is the hero's hex; `jump` [from, to] plays a cavalry first jump
  # and selects the horse where it lands; `focus` centres the crops (the hero
  # by default); `last` is the opponent's last move, marked orange.
  SCENES = {
    "dragon" => {
      select: 75, last: [ 16, 35 ], turn: 14,
      units: [
        [ 1, "dragon", 75 ], [ 1, "mountain", 66 ], [ 1, "king", 88 ], [ 1, "crossbowman", 80 ], [ 1, "spearman", 74 ],
        [ 1, "elephant", 57 ], [ 1, "rabble", 55 ], [ 1, "catapult", 82 ], [ 1, "heavyhorse", 60 ],
        [ 0, "rabble", 35 ], [ 0, "heavyhorse", 45 ], [ 0, "spearman", 36 ], [ 0, "elephant", 26 ], [ 0, "crossbowman", 17 ],
        [ 0, "king", 4 ], [ 0, "trebuchet", 9 ], [ 0, "lighthorse", 38 ], [ 0, "mountain", 28 ], [ 0, "catapult", 11 ]
      ]
    },
    "trebuchet" => {
      select: 76, last: [ 27, 47 ], turn: 11,
      units: [
        [ 1, "trebuchet", 76 ], [ 1, "king", 86 ], [ 1, "crossbowman", 84 ], [ 1, "elephant", 67 ], [ 1, "spearman", 65 ],
        [ 1, "rabble", 58 ], [ 1, "lighthorse", 70 ], [ 1, "catapult", 81 ],
        [ 0, "lighthorse", 47 ], [ 1, "mountain", 57 ], [ 0, "spearman", 44 ], [ 0, "dragon", 37 ], [ 0, "rabble", 36 ],
        [ 0, "elephant", 34 ], [ 0, "king", 5 ], [ 0, "crossbowman", 26 ], [ 0, "heavyhorse", 29 ]
      ]
    },
    "lighthorse" => {
      jump: [ 64, 55 ], last: [ 25, 35 ], turn: 9,
      units: [
        [ 1, "lighthorse", 64 ], [ 1, "lighthorse", 68 ], [ 1, "spearman", 56 ], [ 1, "elephant", 66 ], [ 1, "king", 87 ],
        [ 1, "crossbowman", 74 ], [ 1, "mountain", 53 ], [ 1, "catapult", 81 ], [ 1, "trebuchet", 83 ],
        [ 0, "rabble", 35 ], [ 0, "crossbowman", 33 ], [ 0, "spearman", 24 ], [ 0, "rabble", 44 ], [ 0, "elephant", 37 ],
        [ 0, "king", 3 ], [ 0, "heavyhorse", 16 ], [ 0, "mountain", 30 ], [ 0, "catapult", 10 ]
      ]
    },
    "elephant" => {
      select: 56, last: [ 25, 45 ], turn: 7,
      units: [
        [ 1, "elephant", 56 ], [ 1, "elephant", 58 ], [ 1, "spearman", 55 ], [ 1, "spearman", 59 ], [ 1, "rabble", 57 ],
        [ 1, "heavyhorse", 65 ], [ 1, "crossbowman", 67 ], [ 1, "king", 76 ], [ 1, "catapult", 75 ], [ 1, "trebuchet", 85 ],
        [ 0, "rabble", 45 ], [ 0, "spearman", 35 ], [ 0, "elephant", 36 ], [ 0, "rabble", 37 ], [ 0, "spearman", 26 ],
        [ 0, "crossbowman", 27 ], [ 0, "king", 4 ], [ 0, "catapult", 16 ]
      ]
    },
    "catapult" => {
      select: 66, last: [ 17, 36 ], turn: 12,
      units: [
        [ 1, "catapult", 66 ], [ 1, "spearman", 56 ], [ 1, "elephant", 58 ], [ 1, "king", 78 ], [ 1, "crossbowman", 73 ],
        [ 1, "heavyhorse", 63 ], [ 1, "rabble", 69 ], [ 1, "mountain", 83 ],
        [ 0, "heavyhorse", 36 ], [ 0, "rabble", 46 ], [ 0, "spearman", 34 ], [ 0, "lighthorse", 38 ], [ 0, "elephant", 25 ],
        [ 0, "dragon", 18 ], [ 0, "king", 2 ], [ 0, "mountain", 35 ]
      ]
    },
    "king" => {
      select: 76, last: [ 12, 39 ], turn: 16,
      units: [
        [ 1, "king", 76 ], [ 1, "spearman", 67 ], [ 1, "spearman", 66 ], [ 1, "crossbowman", 75 ], [ 1, "crossbowman", 78 ],
        [ 1, "elephant", 68 ], [ 1, "catapult", 85 ], [ 1, "trebuchet", 83 ], [ 1, "rabble", 58 ], [ 1, "heavyhorse", 70 ],
        [ 0, "dragon", 39 ], [ 0, "lighthorse", 47 ], [ 0, "heavyhorse", 50 ], [ 0, "rabble", 36 ], [ 0, "elephant", 26 ],
        [ 0, "king", 5 ], [ 0, "crossbowman", 28 ]
      ]
    },
    "mountain" => {
      select: 55, focus: 56, last: [ 36, 46 ], turn: 6,
      units: [
        [ 1, "mountain", 55 ], [ 1, "mountain", 58 ], [ 1, "spearman", 56 ], [ 1, "elephant", 57 ], [ 1, "crossbowman", 64 ],
        [ 1, "catapult", 67 ], [ 1, "heavyhorse", 69 ], [ 1, "king", 77 ], [ 1, "rabble", 60 ], [ 1, "trebuchet", 85 ],
        [ 0, "rabble", 44 ], [ 0, "heavyhorse", 46 ], [ 0, "lighthorse", 50 ], [ 0, "spearman", 47 ], [ 0, "elephant", 35 ],
        [ 0, "rabble", 26 ], [ 0, "king", 4 ], [ 0, "crossbowman", 27 ], [ 0, "catapult", 17 ]
      ]
    },
    "crossbowman" => {
      select: 65, last: [ 24, 44 ], turn: 10,
      units: [
        [ 1, "crossbowman", 65 ], [ 1, "spearman", 55 ], [ 1, "rabble", 56 ], [ 1, "king", 85 ], [ 1, "heavyhorse", 64 ],
        [ 1, "elephant", 67 ], [ 1, "catapult", 74 ], [ 1, "crossbowman", 77 ],
        [ 0, "elephant", 45 ], [ 0, "rabble", 44 ], [ 0, "spearman", 34 ], [ 0, "lighthorse", 36 ], [ 0, "king", 3 ],
        [ 0, "dragon", 15 ], [ 0, "mountain", 37 ], [ 0, "trebuchet", 8 ]
      ]
    },
    "rabble" => {
      select: 56, last: [ 26, 36 ], turn: 5,
      units: [
        [ 1, "rabble", 56 ], [ 1, "rabble", 54 ], [ 1, "rabble", 58 ], [ 1, "spearman", 65 ], [ 1, "spearman", 66 ],
        [ 1, "elephant", 64 ], [ 1, "king", 77 ], [ 1, "crossbowman", 74 ], [ 1, "lighthorse", 69 ], [ 1, "mountain", 60 ],
        [ 0, "rabble", 36 ], [ 0, "rabble", 45 ], [ 0, "spearman", 35 ], [ 0, "elephant", 26 ], [ 0, "heavyhorse", 38 ],
        [ 0, "king", 4 ], [ 0, "crossbowman", 16 ], [ 0, "mountain", 37 ]
      ]
    },
    "spearman" => {
      select: 57, last: [ 36, 47 ], turn: 8,
      units: [
        [ 1, "spearman", 57 ], [ 1, "spearman", 55 ], [ 1, "rabble", 56 ], [ 1, "elephant", 59 ], [ 1, "heavyhorse", 66 ],
        [ 1, "king", 76 ], [ 1, "crossbowman", 67 ], [ 1, "catapult", 74 ], [ 1, "mountain", 61 ],
        [ 0, "lighthorse", 47 ], [ 0, "rabble", 45 ], [ 0, "spearman", 35 ], [ 0, "elephant", 37 ], [ 0, "king", 5 ],
        [ 0, "heavyhorse", 27 ], [ 0, "crossbowman", 16 ], [ 0, "mountain", 32 ]
      ]
    },
    "heavyhorse" => {
      select: 64, last: [ 16, 35 ], turn: 9,
      units: [
        [ 1, "heavyhorse", 64 ], [ 1, "heavyhorse", 69 ], [ 1, "spearman", 56 ], [ 1, "elephant", 66 ], [ 1, "rabble", 53 ],
        [ 1, "king", 86 ], [ 1, "crossbowman", 73 ], [ 1, "catapult", 82 ], [ 1, "mountain", 58 ],
        [ 0, "rabble", 44 ], [ 0, "crossbowman", 35 ], [ 0, "lighthorse", 33 ], [ 0, "spearman", 25 ], [ 0, "elephant", 36 ],
        [ 0, "king", 3 ], [ 0, "catapult", 16 ], [ 0, "mountain", 29 ]
      ]
    }
  }.freeze

  setup do
    @cwebp = `which cwebp`.strip
    raise "cwebp not found: brew install webp" if @cwebp.empty?

    FileUtils.mkdir_p(OUT)
    FileUtils.mkdir_p(PREVIEWS) if ENV["PREVIEW"]
    visit play_path
    page.execute_script("localStorage.clear(); document.documentElement.classList.add('dark')")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit play_path
    select "Crown Forward", from: "Opening"
    within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
    assert_text "Loaded Crown Forward."
    click_on "Ready"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    assert_equal "vector", find("[data-controller=cyvasse-game]")["data-skin"]
  end

  test "capture one action shot per piece" do
    wanted = ENV["PIECES"]&.split(",")&.map(&:strip)
    slides = HomeGallery::SLIDES.select { |slide| wanted.nil? || wanted.include?(slide.slug) }
    assert_equal HomeGallery::SLIDES.map(&:slug).sort, SCENES.keys.sort, "one scene per slide"

    slides.each do |slide|
      scene = SCENES.fetch(slide.slug)
      stage(slide.slug, scene)
      capture(slide.slug, scene)
    end
  end

  private

  # Put every unit of the scene on the board (the rest of both armies fall),
  # hand the move to the player and select the hero as a click would.
  def stage(slug, scene)
    hero = page.evaluate_script(<<~JS)
      (() => {
        const ctrl = #{CONTROLLER}
        const game = ctrl.game
        ctrl.clearTimers()
        ctrl.hideBanner()
        ctrl.clearSelection()
        for (const unit of game.units) { unit.status = "dead"; unit.hex = null }
        for (const [team, codename, hex] of #{scene.fetch(:units).to_json}) {
          const unit = game.units.find((u) => u.team === team && u.type.codename === codename && u.status === "dead" && u.hex === null && !u.placed)
          if (!unit) throw new Error(`no ${codename} left for team ${team}`)
          unit.status = "alive"
          unit.hex = hex
          unit.placed = true
        }
        for (const unit of game.units) delete unit.placed
        Object.assign(game, { phase: "play", turn: #{scene.fetch(:turn)}, offense: 1, jump: 1, activeHex: null,
          lastMove: #{scene.fetch(:last).to_json}, utilMove: null, winner: null })
        ctrl.holding = false
        ctrl.pendingJump = null
        ctrl.render()
        const jump = #{scene[:jump].to_json}
        if (jump) {
          ctrl.select(jump[0])
          ctrl.playClick(jump[1])
        } else {
          ctrl.select(#{scene[:select].to_json})
        }
        ctrl.moveCursor(ctrl.hoverCursor, null)
        ctrl.moveCursor(ctrl.focusCursor, null)
        const unit = game.pieceAt(ctrl.selectedHex)
        return { hex: ctrl.selectedHex, codename: unit.type.codename, team: unit.team,
                 moves: ctrl.actions.moves.length, attacks: ctrl.actions.attacks.length, jump: game.jump }
      })()
    JS
    assert_equal slug, hero["codename"], "#{slug}: the selected unit is the hero"
    assert_equal 1, hero["team"], "#{slug}: the hero is the player's"
    puts "#{slug}: hex #{hero['hex']}, #{hero['moves']} moves, #{hero['attacks']} attacks, jump #{hero['jump']}"
    assert_selector ".cyvasse-banner", visible: :hidden
  end

  def capture(slug, scene)
    focus = scene[:focus] || page.evaluate_script("#{CONTROLLER}.selectedHex")
    board = page.evaluate_script(<<~JS)
      (() => {
        const ctrl = #{CONTROLLER}
        const svg = ctrl.boardTarget
        // Board units to page pixels: the element box can be letterboxed
        // around the drawing, so read the drawing's own transform.
        const ctm = svg.getScreenCTM()
        const view = svg.viewBox.baseVal
        const centre = ctrl.hexCentres.get(#{focus})
        return { left: ctm.e + window.scrollX, top: ctm.f + window.scrollY, scale: ctm.a,
                 width: view.width, height: view.height, cx: centre.x, cy: centre.y }
      })()
    JS

    shot(board, { x: 0, y: 0, width: board["width"], height: board["height"] }, 1600, PREVIEWS.join("#{slug}-board.png")) if ENV["PREVIEW"]
    { "" => DESKTOP, "-mobile" => MOBILE }.each do |suffix, crop|
      rect = crop_around(board, crop)
      png = PREVIEWS.join("#{slug}#{suffix}.png")
      FileUtils.mkdir_p(PREVIEWS)
      shot(board, rect, crop[:pixels], png)
      webp = OUT.join("#{slug}#{suffix}.webp")
      encode(png, webp)
    end
  end

  # A crop of the given size centred as near the focus as its reach allows.
  def crop_around(board, crop)
    mid_x = board["width"] / 2.0
    mid_y = board["height"] / 2.0
    cx = board["cx"].clamp(mid_x - crop[:reach][:x], mid_x + crop[:reach][:x])
    cy = board["cy"].clamp(mid_y - crop[:reach][:y], mid_y + crop[:reach][:y])
    x = (cx - crop[:width] / 2.0).clamp(0, board["width"] - crop[:width])
    y = (cy - crop[:height] / 2.0).clamp(0, board["height"] - crop[:height])
    { x:, y:, width: crop[:width], height: crop[:height] }
  end

  # A PNG of a board-unit rectangle, `pixels` wide.
  def shot(board, rect, pixels, path)
    css = board["scale"]
    clip = { x: board["left"] + rect[:x] * css, y: board["top"] + rect[:y] * css,
             width: rect[:width] * css, height: rect[:height] * css }
    clip[:scale] = pixels / clip[:width]
    data = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", captureBeyondViewport: true, clip:)
    File.binwrite(path, Base64.decode64(data.fetch("data")))
  end

  # The smallest file under the cap, stepping the quality down from QUALITY.
  def encode(png, webp)
    QUALITY.step(40, -4) do |quality|
      system(@cwebp, "-quiet", "-q", quality.to_s, "-m", "6", "-metadata", "none", png.to_s, "-o", webp.to_s, exception: true)
      break if File.size(webp) <= MAX_BYTES
    end
    puts "  #{webp.relative_path_from(Rails.root)}: #{File.size(webp)} bytes"
    assert_operator File.size(webp), :<=, MAX_BYTES, "#{webp} is under the cap"
  end
end
