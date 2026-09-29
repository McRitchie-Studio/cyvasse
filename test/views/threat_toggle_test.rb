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
end
