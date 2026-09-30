require "application_system_test_case"

# [e2e] The pieces on the board come in three sizes (units.js sizeTier, scaled
# in game.css): small (rabble, spearman, crossbowman), medium (king, light and
# heavy horse) and large (trebuchet, catapult, elephant, dragon, mountain), in
# both skins and for both armies. The old team shade that deepened with a
# piece's worth is gone: every piece takes the same faint rim of its team's
# colour. The art never takes a click from the hex under it. Where the art may
# reach (cut at its hex's right and lower sides, free past the upper ones) is
# test/system/piece_art_overlap_test.rb's.
#
# PIECE_TIER_SHOTS=<dir> saves the board as size-tiers-<skin>-<phase>.png.
class PieceSizeTiersTest < ApplicationSystemTestCase
  TIERS = {
    "small" => %w[rabble spearman crossbowman],
    "medium" => %w[king lighthorse heavyhorse],
    "large" => %w[trebuchet catapult elephant dragon mountain]
  }.freeze

  # The small tier's width in board units: 1.1 times the vector art's 56-unit
  # box, and 1.1 times the pencil token's old disc (radius 27 at 0.83).
  SMALL_WIDTH = { "vector" => 56 * 1.1, "pencil" => 54 * 0.83 * 1.1 }.freeze

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
      assert_art_takes_no_click pieces
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
      assert_art_takes_no_click pieces
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
    widths = pieces.group_by { |piece| piece["tier"] }.transform_values { |group| group.map { |piece| width_of(piece, skin) } }
    assert_operator widths.fetch("large").min, :>, widths.fetch("medium").max, "#{skin}: every large piece draws wider than every medium one (#{widths.inspect})"
    assert_operator widths.fetch("medium").min, :>, widths.fetch("small").max, "#{skin}: every medium piece draws wider than every small one (#{widths.inspect})"
    # Every tier is a step up from the art's own size (task
    # cyvasse-piece-art-overlap): the small tier draws 1.1 times what it did.
    SMALL_WIDTH.fetch(skin).then { |width| assert_in_delta width, widths.fetch("small").min, 0.5, "#{skin}: the small tier draws 1.1 times its old size" }
  end

  # Pencil sizes the token, disc and drawing together; vector the drawing.
  def width_of(piece, skin)
    rendered = skin == "pencil" ? piece["disc"]["width"] : piece["box"]["width"]
    (rendered / piece["unit_px"]).round(2)
  end

  # The hex polygon under the art is the whole hit target.
  def assert_art_takes_no_click(pieces)
    pieces.each do |piece|
      assert_equal "none", piece["pointer_events"], "the #{piece["unit"]} art never takes the hex's click"
      assert_equal "none", piece["disc_pointer_events"], "the #{piece["unit"]} disc never takes the hex's click"
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
  # screen, and whether either takes a click.
  def measure
    page.evaluate_script(<<~JS)
      (() => {
        const rect = (r) => ({ left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height });
        const board = document.querySelector(".cyvasse-board");
        const unitPx = board.getBoundingClientRect().width / board.viewBox.baseVal.width;
        return [...document.querySelectorAll("g.hex.has-unit")].map((group) => {
          const image = group.querySelector(".unit-image");
          const disc = group.querySelector(".unit-disc");
          return {
            hex: group.dataset.hex, unit: group.dataset.unit, tier: group.dataset.tier, team: group.dataset.team,
            unit_px: unitPx, box: rect(image.getBoundingClientRect()), disc: rect(disc.getBoundingClientRect()),
            pointer_events: getComputedStyle(image).pointerEvents, disc_pointer_events: getComputedStyle(disc).pointerEvents
          };
        });
      })()
    JS
  end

  def shot(skin, phase)
    dir = ENV["PIECE_TIER_SHOTS"]
    return unless dir

    page.execute_script("document.documentElement.classList.add('dark')")
    page.save_screenshot(File.join(dir, "size-tiers-#{skin}-#{phase}.png"))
  end
end
