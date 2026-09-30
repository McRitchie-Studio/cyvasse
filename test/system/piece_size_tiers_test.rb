require "application_system_test_case"

# [e2e] The pieces on the board come in three sizes (units.js sizeTier, scaled
# in game.css): small (rabble, spearman, crossbowman), medium (king, light and
# heavy horse) and large (trebuchet, catapult, elephant, dragon, mountain), in
# both skins and for both armies. The old team shade that deepened with a
# piece's worth is gone: every piece takes the same faint rim of its team's
# colour. However large, no drawing leaves the box of its hex's white outline,
# and the art never takes a click from the hex under it.
#
# PIECE_TIER_SHOTS=<dir> saves the board as size-tiers-<skin>-<phase>.png.
class PieceSizeTiersTest < ApplicationSystemTestCase
  TIERS = {
    "small" => %w[rabble spearman crossbowman],
    "medium" => %w[king lighthorse heavyhorse],
    "large" => %w[trebuchet catapult elephant dragon mountain]
  }.freeze

  # Vector art that already fills its canvas is capped in game.css (--art-fit)
  # so it stays in its hex: the dragon (1.06 of its box), the elephant (1.08)
  # and the mountain (0.9; it was 0.86). Each grows less than a medium piece's
  # box, but it was already drawn large: it must still draw larger than it
  # did, and its drawing must still outsize every medium drawing.
  CAPPED = { "vector" => { "dragon" => 1.0, "elephant" => 1.0, "mountain" => 0.86 }, "pencil" => {} }.freeze
  BOX_WIDTH = 56 # the art's box in board units (cyvasse_game_controller buildBoard)

  %w[vector pencil].each do |skin|
    test "#{skin}: large art draws bigger than medium, medium than small, all inside the hex, one uniform team rim" do
      visit play_path(skin: skin)
      assert_selector "[data-controller=cyvasse-game][data-skin=#{skin}][data-phase=setup]"
      assert_controllers_connected "cyvasse-game", "cyvasse-openings"
      select "Crown Forward", from: "Opening"
      within("[data-controller=cyvasse-openings]") { click_on "Load opening" }
      assert_selector "g.hex.has-unit[data-team='1']", count: 19
      shot(skin, "setup")

      pieces = measure
      assert_equal 19, pieces.size
      assert_tiers pieces, skin
      assert_inside_hexes pieces
      assert_uniform_rim team: 1

      click_on "Ready"
      assert_selector "[data-controller=cyvasse-game][data-phase=play]"
      assert_selector "g.hex.has-unit", count: 38
      shot(skin, "play")

      pieces = measure
      assert_equal 38, pieces.size
      enemy = pieces.select { |piece| piece["team"] == "0" }
      assert_equal 19, enemy.size
      assert_tiers enemy, skin
      assert_inside_hexes pieces
      assert_uniform_rim team: 0
    end
  end

  private

  # Each tier's art box is wider than every box of the tier below it, in the
  # hex's own units (the board's pixel scale divided out).
  def assert_tiers(pieces, skin)
    pieces.each do |piece|
      expected = TIERS.find { |_, units| units.include?(piece["unit"]) }&.first
      assert_equal expected, piece["tier"], "#{piece["unit"]} on hex #{piece["hex"]} is #{expected}"
    end
    widths = pieces.group_by { |piece| piece["tier"] }.transform_values { |group| group.map { |piece| [ piece["unit"], width_of(piece, skin) ] } }
    small = widths.fetch("small").map(&:last)
    medium = widths.fetch("medium").map(&:last)
    capped = CAPPED.fetch(skin)
    large = widths.fetch("large").reject { |unit, _| capped.key?(unit) }.map(&:last)
    assert_operator large.min, :>, medium.max, "#{skin}: every large piece draws wider than every medium one (#{widths.inspect})"
    assert_operator medium.min, :>, small.max, "#{skin}: every medium piece draws wider than every small one (#{widths.inspect})"

    medium_drawing = pieces.select { |piece| piece["tier"] == "medium" }.map { |piece| extent_of(piece) }.max
    pieces.select { |piece| capped.key?(piece["unit"]) }.each do |piece|
      assert_operator width_of(piece, skin), :>, capped.fetch(piece["unit"]) * BOX_WIDTH, "#{skin}: the #{piece["unit"]} draws larger than it did"
      assert_operator extent_of(piece), :>, medium_drawing, "#{skin}: the #{piece["unit"]}'s drawing outsizes every medium drawing"
    end
  end

  # The longer side of the drawing's opaque pixels, in board units.
  def extent_of(piece)
    art = piece["art"]
    ([ art["right"] - art["left"], art["bottom"] - art["top"] ].max / piece["unit_px"]).round(2)
  end

  # Pencil sizes the token, disc and drawing together; vector the drawing.
  def width_of(piece, skin)
    rendered = skin == "pencil" ? piece["disc"]["width"] : piece["box"]["width"]
    (rendered / piece["unit_px"]).round(2)
  end

  # The drawn pixels (not the transparent box around them) and, in pencil, the
  # parchment disc stay within the box of the hex's white outline.
  def assert_inside_hexes(pieces)
    pieces.each do |piece|
      hex = piece["hex_rect"]
      shapes = { "art" => piece["art"] }
      shapes["disc"] = piece["disc"] if piece["skin"] == "pencil"
      shapes.each do |name, rect|
        %w[left top].each { |side| assert_operator rect[side], :>=, hex[side] - 0.5, "#{piece["unit"]} #{name} crosses its hex's #{side} (hex #{piece["hex"]})" }
        %w[right bottom].each { |side| assert_operator rect[side], :<=, hex[side] + 0.5, "#{piece["unit"]} #{name} crosses its hex's #{side} (hex #{piece["hex"]})" }
      end
      assert_equal "none", piece["pointer_events"], "the #{piece["unit"]} art never takes the hex's click"
    end
  end

  # One gradient per team, the same fill on every piece: nothing graded by
  # what the piece is worth.
  def assert_uniform_rim(team:)
    ids = page.evaluate_script("[...document.querySelectorAll('.cyvasse-board defs radialGradient[id^=shade-]')].map((g) => g.id).sort()")
    assert_equal %w[shade-0 shade-1], ids
    fills = page.evaluate_script("[...document.querySelectorAll(\"g.hex.has-unit[data-team='#{team}'] .unit-shade\")].map((s) => s.getAttribute('fill'))")
    assert_equal [ "url(#shade-#{team})" ], fills.uniq
  end

  # Every placed piece: its unit, tier and team, its art box and disc on
  # screen, the rect of the art's opaque pixels (from the image's own alpha,
  # drawn as the board draws it: centred and fitted in the box), and its hex
  # outline's rect.
  def measure
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      (async () => {
        const skin = document.querySelector("[data-controller~=cyvasse-game]").dataset.skin;
        const bounds = new Map();
        const opaque = async (href) => {
          if (bounds.has(href)) return bounds.get(href);
          const img = new Image(); img.src = href; await img.decode();
          const S = 4, BW = 56 * S, BH = 60 * S;
          const canvas = document.createElement("canvas"); canvas.width = BW; canvas.height = BH;
          const ctx = canvas.getContext("2d");
          const k = Math.min(BW / img.naturalWidth, BH / img.naturalHeight);
          const w = img.naturalWidth * k, h = img.naturalHeight * k;
          ctx.drawImage(img, (BW - w) / 2, (BH - h) / 2, w, h);
          const data = ctx.getImageData(0, 0, BW, BH).data;
          let x0 = BW, x1 = -1, y0 = BH, y1 = -1;
          for (let y = 0; y < BH; y++) for (let x = 0; x < BW; x++) {
            if (data[(y * BW + x) * 4 + 3] > 40) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
          }
          const found = { left: x0 / BW, right: (x1 + 1) / BW, top: y0 / BH, bottom: (y1 + 1) / BH };
          bounds.set(href, found);
          return found;
        };
        const rect = (r) => ({ left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height });
        const board = document.querySelector(".cyvasse-board");
        const unitPx = board.getBoundingClientRect().width / board.viewBox.baseVal.width;
        const pieces = [];
        for (const group of document.querySelectorAll("g.hex.has-unit")) {
          const image = group.querySelector(".unit-image");
          const box = image.getBoundingClientRect();
          const fraction = await opaque(image.getAttribute("href"));
          pieces.push({
            hex: group.dataset.hex, unit: group.dataset.unit, tier: group.dataset.tier, team: group.dataset.team, skin,
            unit_px: unitPx,
            box: rect(box),
            art: {
              left: box.left + fraction.left * box.width, right: box.left + fraction.right * box.width,
              top: box.top + fraction.top * box.height, bottom: box.top + fraction.bottom * box.height
            },
            disc: rect(group.querySelector(".unit-disc").getBoundingClientRect()),
            hex_rect: rect(group.querySelector(".hex-poly").getBoundingClientRect()),
            pointer_events: getComputedStyle(image).pointerEvents
          });
        }
        done(pieces);
      })().catch((error) => done({ error: String(error) }));
    JS
  end

  def shot(skin, phase)
    dir = ENV["PIECE_TIER_SHOTS"]
    return unless dir

    page.execute_script("document.documentElement.classList.add('dark')")
    page.save_screenshot(File.join(dir, "size-tiers-#{skin}-#{phase}.png"))
  end
end
