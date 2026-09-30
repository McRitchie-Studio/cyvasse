require "application_system_test_case"

# [e2e] A piece stands on its tile (task cyvasse-piece-art-overlap): its art,
# and the pencil skin's parchment disc, are cut along its hex's right,
# lower-right and lower-left sides and may rise over the hexes behind it, past
# the upper-right, upper-left and left sides (cyvasse/art_clip). The hexes draw
# back to front, so the rising art covers the hexes behind it; the highlight
# borders, the threat outline among them, draw over all of it; and the art
# never takes a click, so a hex under a neighbour's art still answers its own.
#
# The pixels are the browser's own: the board is shot with every piece's art
# hidden, then with one piece's art shown at a time, and the pixels that
# differ are that piece's drawing, clip and all.
#
# ART_OVERLAP_SHOTS=<dir> saves the board as art-overlap-<skin>.png (dark).
class PieceArtOverlapTest < ApplicationSystemTestCase
  W = 60.0
  H = W * 2 / Math.sqrt(3)
  TOLERANCE = 1.0 # board units, for antialiasing along the cut

  %w[vector pencil].each do |skin|
    test "#{skin}: art is cut at its hex's right and lower sides, rises past its upper ones, and never hides a click or the threat outline" do
      visit play_path(skin: skin)
      assert_selector "[data-controller=cyvasse-game][data-skin=#{skin}][data-phase=setup]"
      assert_controllers_connected "cyvasse-game", "cyvasse-openings"
      select "Crown Forward", from: "Opening"
      within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
      assert_selector "g.hex.has-unit[data-team='1']", count: 19
      click_on "Ready"
      assert_selector "[data-controller=cyvasse-game][data-phase=play]"
      assert_selector "g.hex.has-unit", count: 38
      still_board
      shot(skin)

      assert_paint_order
      pieces = measure(skin)
      assert_equal 38, pieces.size

      pieces.each do |piece|
        assert_operator piece["pixels"], :>, 50, "#{skin}: the #{piece["unit"]} on hex #{piece["hex"]} draws something"
        assert_equal 0, piece["forbidden"],
          "#{skin}: the #{piece["unit"]} on hex #{piece["hex"]} draws #{piece["forbidden"]} pixel(s) past its right or lower sides (#{piece["worst"].inspect})"
      end
      pieces.select { |piece| piece["tier"] == "large" }.each do |piece|
        assert_operator piece["upper_reach"], :>, 2,
          "#{skin}: the large #{piece["unit"]} on hex #{piece["hex"]} rises past its hex's upper sides"
      end
      assert_threat_outline_over_art pieces, skin
      assert_click_under_art_selects pieces, skin
    end
  end

  private

  # The hexes draw in reading order, rows top to bottom and each row left to
  # right, each hex's art after its own fills, and every highlight border and
  # the cursors after every hex.
  def assert_paint_order
    order = page.evaluate_script(<<~JS)
      (() => {
        const svg = document.querySelector(".cyvasse-board");
        const kids = [...svg.children];
        const hexes = kids.filter((node) => node.matches("g.hex"));
        const centres = hexes.map((g) => { const m = g.transform.baseVal.consolidate().matrix; return [m.f, m.e]; });
        const artLast = hexes.every((g) => g.lastElementChild.matches(".unit-art") && g.querySelector(".unit-art .unit-disc"));
        const edges = kids.findIndex((node) => node.matches(".hex-edges"));
        return { centres, artLast, lastHex: kids.indexOf(hexes.at(-1)), edges };
      })()
    JS
    assert_equal 91, order["centres"].size
    assert_equal order["centres"].sort, order["centres"], "hexes draw top to bottom, then left to right"
    assert order["artLast"], "each hex draws its art (and the pencil disc) after its own fills"
    assert_operator order["edges"], :>, order["lastHex"], "the highlight borders draw over every hex's art"
  end

  # The board holds still for the camera: no pulse, fade or cursor.
  def still_board
    page.execute_script(<<~JS)
      const style = document.createElement("style");
      style.id = "art-overlap-still";
      style.textContent = "*, *::before, *::after { animation: none !important; transition: none !important; } .cyvasse-board .hex-cursor { display: none !important; }";
      document.head.append(style);
    JS
  end

  def board_shot
    rect = page.evaluate_script(<<~JS)
      (() => { const r = document.querySelector(".cyvasse-board").getBoundingClientRect();
        return { x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height }; })()
    JS
    page.driver.browser.execute_cdp("Page.captureScreenshot", format: "png", captureBeyondViewport: true,
      clip: rect.merge("scale" => 1))["data"]
  end

  def show_art(hex)
    page.execute_script(<<~JS, hex)
      for (const art of document.querySelectorAll(".cyvasse-board .unit-art")) {
        art.style.visibility = art.closest("g.hex").dataset.hex === String(arguments[0]) ? "visible" : "hidden";
      }
    JS
  end

  # Each piece's drawn pixels, from the difference between the board with
  # only its art shown and the board with no art at all, in board units about
  # its hex's centre: how many land past its right or lower sides (inside the
  # hex to its right, either hex below it, or below its bottom corner), and
  # how far any rises past its upper-left or upper-right side. Each piece also
  # keeps the board-unit points it drew, for the outline and click checks.
  def measure(skin)
    hexes = page.evaluate_script("[...document.querySelectorAll('g.hex.has-unit')].map((g) => g.dataset.hex)")
    show_art(nil)
    page.evaluate_async_script(<<~JS, board_shot)
      const done = arguments[arguments.length - 1];
      window.__artBase = null;
      const img = new Image(); img.src = "data:image/png;base64," + arguments[0];
      img.decode().then(() => {
        const canvas = document.createElement("canvas"); canvas.width = img.width; canvas.height = img.height;
        const ctx = canvas.getContext("2d"); ctx.drawImage(img, 0, 0);
        window.__artBase = ctx.getImageData(0, 0, img.width, img.height);
        done(true);
      }).catch((e) => done(String(e)));
    JS
    pieces = hexes.map { |hex| show_art(hex); analyse(hex, board_shot) }
    page.execute_script("for (const art of document.querySelectorAll('.cyvasse-board .unit-art')) art.style.visibility = ''")
    pieces
  end

  def analyse(hex, png)
    page.evaluate_async_script(<<~JS, hex, png, W, H, TOLERANCE)
      const [hex, png, W, H, TOL, done] = arguments;
      (async () => {
        const img = new Image(); img.src = "data:image/png;base64," + png; await img.decode();
        const canvas = document.createElement("canvas"); canvas.width = img.width; canvas.height = img.height;
        const ctx = canvas.getContext("2d"); ctx.drawImage(img, 0, 0);
        const shot = ctx.getImageData(0, 0, img.width, img.height).data;
        const base = window.__artBase.data;
        const svg = document.querySelector(".cyvasse-board");
        const group = svg.querySelector(`g.hex[data-hex="${hex}"]`);
        const rect = svg.getBoundingClientRect();
        const toBoard = svg.getScreenCTM().inverse();
        const m = group.transform.baseVal.consolidate().matrix;
        const kx = rect.width / img.width, ky = rect.height / img.height;
        // A point inside a pointy-top hex of full size (W x H) centred at (cx, cy), shrunk by TOL.
        const inHex = (x, y, cx, cy) => {
          const dx = Math.abs(x - cx), dy = Math.abs(y - cy), w = W / 2 - TOL, h = H / 2 - TOL * 2 / Math.sqrt(3);
          return dx <= w && dy <= h - dx * (h / 2) / w;
        };
        const s = 0.97, hw = W / 2 * s, hq = H / 4 * s, hh = H / 2 * s;
        // Outward distance past the upper-right and upper-left sides.
        const n = Math.hypot(hq, hw);
        const pastUpper = (x, y) => Math.max((hq * x - hw * y - hw * hh) / n, (-hq * x - hw * y - hw * hh) / n);
        let pixels = 0, forbidden = 0, upper = -Infinity, worst = null;
        const points = [];
        const p = svg.createSVGPoint();
        for (let py = 0; py < img.height; py++) for (let px = 0; px < img.width; px++) {
          const i = (py * img.width + px) * 4;
          if (Math.abs(shot[i] - base[i]) + Math.abs(shot[i + 1] - base[i + 1]) + Math.abs(shot[i + 2] - base[i + 2]) < 36) continue;
          p.x = rect.left + (px + 0.5) * kx; p.y = rect.top + (py + 0.5) * ky;
          const b = p.matrixTransform(toBoard);
          const x = b.x - m.e, y = b.y - m.f;
          pixels++;
          points.push([Math.round(b.x * 10) / 10, Math.round(b.y * 10) / 10]);
          const bad = inHex(x, y, W, 0) || inHex(x, y, W / 2, 0.75 * H) || inHex(x, y, -W / 2, 0.75 * H) || y > hh + TOL;
          if (bad) { forbidden++; worst ??= [Math.round(x * 10) / 10, Math.round(y * 10) / 10]; }
          upper = Math.max(upper, pastUpper(x, y));
        }
        done({ hex, unit: group.dataset.unit, tier: group.dataset.tier, team: group.dataset.team,
               centre: [m.e, m.f], pixels, forbidden, worst, upper_reach: Math.round(upper * 10) / 10, points });
      })().catch((e) => done({ error: String(e) }));
    JS
  end

  # A solid threat line that some piece's art spans (drawn pixels on both
  # sides of it, along it) is not changed along its middle by that art: the
  # outline draws over the art. The art under the line proves the check bites.
  def assert_threat_outline_over_art(pieces, skin)
    lines = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".cyvasse-board .hex-edge[data-kind='perimeter'], .cyvasse-board .hex-edge[data-kind='danger']")]
        .map((l) => [l.dataset.kind, +l.getAttribute("x1"), +l.getAttribute("y1"), +l.getAttribute("x2"), +l.getAttribute("y2")])
    JS
    refute_empty lines, "#{skin}: the threat outline is on"
    spanned = []
    pieces.each do |piece|
      lines.each do |kind, x1, y1, x2, y2|
        len = Math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / len, (y2 - y1) / len
        near = { 1 => 0, -1 => 0 }
        on_line = 0
        piece["points"].each do |x, y|
          t = (x - x1) * ux + (y - y1) * uy
          next unless t > len * 0.2 && t < len * 0.8
          d = (x - x1) * -uy + (y - y1) * ux
          on_line += 1 if d.abs < 0.6
          near[d.positive? ? 1 : -1] += 1 if d.abs.between?(2.5, 6)
        end
        next unless near.values.all? { |count| count >= 3 }
        spanned << [ piece["unit"], piece["hex"], kind ]
        assert_equal 0, on_line, "#{skin}: the #{piece["unit"]} on hex #{piece["hex"]} draws over the #{kind} line"
      end
    end
    refute_empty spanned, "#{skin}: some piece's art spans a threat line, so the check bites"
  end

  # A point of a hex's own that the art of the hex below it covers: a click
  # there picks the hex's own piece (aria-pressed), not the one whose art is there.
  def assert_click_under_art_selects(pieces, skin)
    player = pieces.select { |piece| piece["team"] == "1" }
    target = nil
    player.each do |front|
      player.each do |behind|
        dx = behind["centre"][0] - front["centre"][0]
        dy = behind["centre"][1] - front["centre"][1]
        next unless (dy + 0.75 * H).abs < 1 && (dx.abs - W / 2).abs < 1
        point = front["points"].find do |x, y|
          rx, ry = (x - behind["centre"][0]).abs, (y - behind["centre"][1]).abs
          rx < W / 2 * 0.8 && ry < H / 2 * 0.8 - rx * 0.3 && ry > 4
        end
        target = [ behind, front, point ] if point
        break if target
      end
      break if target
    end
    assert target, "#{skin}: some piece's art covers part of the hex behind it that holds a piece of the player's"
    behind, front, (x, y) = target
    client = page.evaluate_script(<<~JS, x, y)
      (() => { const svg = document.querySelector(".cyvasse-board"); const p = svg.createSVGPoint(); p.x = arguments[0]; p.y = arguments[1];
        const c = p.matrixTransform(svg.getScreenCTM()); const hit = document.elementFromPoint(c.x, c.y)?.closest("[data-hex]");
        return { x: c.x, y: c.y, hit: hit?.dataset.hex }; })()
    JS
    assert_equal behind["hex"], client["hit"], "#{skin}: under the #{front["unit"]}'s art the hit is hex #{behind["hex"]}"
    page.driver.browser.action.move_to_location(client["x"].round, client["y"].round).click.perform
    assert_selector "g.hex[data-hex='#{behind["hex"]}'][aria-pressed='true']"
    assert_no_selector "g.hex[data-hex='#{front["hex"]}'][aria-pressed='true']"
  end

  def shot(skin)
    dir = ENV["ART_OVERLAP_SHOTS"]
    return unless dir

    page.execute_script("document.documentElement.classList.add('dark')")
    page.save_screenshot(File.join(dir, "art-overlap-#{skin}.png"))
  end
end
