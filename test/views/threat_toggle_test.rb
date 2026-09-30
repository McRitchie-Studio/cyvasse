require "test_helper"

# [component] The threat switches, rendered alone: one per threat group, both
# checked, wired to the board named, and hidden until the board is in play.
class ThreatToggleTest < ActionView::TestCase
  test "renders a Ranged and a Melee switch for the board" do
    render partial: "games/threat_toggle", locals: { board: "cyvasse-match" }

    assert_select ".cyvasse-threat-toggles[hidden]", 1 do
      assert_select "label.cyvasse-threat-toggle", 2
      assert_select "label", text: "Ranged threats" do
        assert_select "input[type=checkbox][checked][data-threat-group=ranged][data-cyvasse-match-target=threatToggle][data-action='cyvasse-match#toggleThreats']"
      end
      assert_select "label", text: "Melee threats" do
        assert_select "input[type=checkbox][checked][data-threat-group=melee][data-cyvasse-match-target=threatToggle][data-action='cyvasse-match#toggleThreats']"
      end
    end
    assert_no_match(/Show threats/, rendered)
  end

  test "renders the board key: a closed disclosure with one swatch per board look" do
    render partial: "games/threat_toggle", locals: { board: "cyvasse-game" }

    assert_select ".cyvasse-threat-toggles[hidden] details.cyvasse-legend:not([open])", 1 do
      assert_select "summary", text: /Board key/
      assert_select ".cyvasse-legend-entry", BoardLegendHelper::BOARD_LEGEND.size
      BoardLegendHelper::BOARD_LEGEND.each do |entry|
        assert_select ".cyvasse-legend-entry[data-legend='#{entry.key}']", 1 do
          assert_select "svg.cyvasse-legend-swatch[data-swatch='#{entry.key}'][aria-hidden=true] polygon", 1
          assert_select "span", text: entry.label
        end
      end
    end
    %w[selected last-move yours enemy move attack sunken reach danger focus].each do |key|
      assert_select ".cyvasse-legend-entry[data-legend=#{key}]", 1, "the key explains #{key}"
    end
  end

  # The key is only as good as its match to the board: every look it names is
  # one the board code draws, each has a swatch style, and every highlight
  # edge the board draws (cyvasse/edges EDGE_PRIORITY) has an entry.
  test "the board key matches the looks the board draws" do
    board_code = %w[
      app/javascript/controllers/cyvasse_game_controller.js
      app/javascript/cyvasse/edges.js
      app/assets/stylesheets/game.css
    ].map { |path| Rails.root.join(path).read }.join("\n")
    css = Rails.root.join("app/assets/stylesheets/game.css").read
    marks = BoardLegendHelper::BOARD_LEGEND.flat_map(&:marks)

    marks.each { |mark| assert_includes board_code, mark, "#{mark} is drawn by the board" }
    assert_equal marks.uniq, marks, "each look is explained once"
    BoardLegendHelper::BOARD_LEGEND.each do |entry|
      assert_includes css, %(.cyvasse-legend-swatch[data-swatch="#{entry.key}"]), "#{entry.key} has a swatch style"
    end

    edges = Rails.root.join("app/javascript/cyvasse/edges.js").read
    kinds = edges[/EDGE_PRIORITY = Object\.freeze\(\[(.*?)\]\)/m, 1].scan(/"([^"]+)"/).flatten
    assert_operator kinds.size, :>=, 10, "EDGE_PRIORITY was read"
    kinds.each { |kind| assert_includes marks, kind, "edge kind #{kind} has a key entry" }
  end
end
