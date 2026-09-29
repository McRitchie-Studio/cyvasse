require "test_helper"

# [component] The setup panel's army card (games/_army_card) and the fallen
# card (games/_fallen_card), rendered alone: Smart Setup comes first under a
# centred heading, the instructions are for screen readers only, Ready is
# disabled, the placed count is announced, the sparkle is silent, and the
# fallen card arrives hidden.
class ArmyCardTest < ActionView::TestCase
  test "Smart Setup leads the card under a centred heading, with no instruction text on show" do
    render partial: "games/army_card", locals: { board: "cyvasse-game" }

    assert_select ".card.cyvasse-army[data-army-mode=smart][data-cyvasse-game-target=army]" do
      assert_select "> h2.text-center", text: "Your army"
      assert_select "> *:not(.sr-only)", text: /Pick a unit/, count: 0
      assert_select "> p.sr-only#cyvasse-game-army-hint", text: /Pick a unit, then a lit hex/
      assert_select "button.cyvasse-smart[data-action='cyvasse-game#smartSetup']", text: "✨ Smart Setup"
      assert_select "button.cyvasse-ready[disabled][data-cyvasse-game-target=startButton]", text: "Ready"
      assert_select ".cyvasse-dock[data-cyvasse-game-target=dock][aria-describedby=cyvasse-game-army-hint]"
    end
    buttons = css_select(".cyvasse-army button").map { |b| b.text.strip }
    assert_equal [ "✨ Smart Setup", "Ready" ], buttons, "Smart Setup comes first"
  end

  test "the count is a polite live region and the sparkle is hidden from screen readers" do
    render partial: "games/army_card", locals: { board: "cyvasse-game" }

    assert_select "p.cyvasse-army-count[data-cyvasse-game-target=armyCount][aria-live=polite][aria-atomic=true]"
    assert_select "p.cyvasse-army-count[aria-hidden]", false, "the count is no longer hidden from screen readers"
    assert_select "button.cyvasse-smart" do
      assert_select "> span[aria-hidden=true]", text: "✨", count: 1
      assert_select "> span[data-smart-label]:not([aria-hidden])", text: "Smart Setup"
    end
    visible = css_select("button.cyvasse-smart").first.children.reject { |node| node["aria-hidden"] == "true" }
    assert_equal "Smart Setup", visible.map(&:text).join.strip, "the button reads Smart Setup, not sparkles"
  end

  test "a match's lock-in note goes to screen readers with the hint" do
    render partial: "games/army_card", locals: { board: "cyvasse-match", note: "Once you press Ready, your army is locked in." }

    assert_select "p.sr-only#cyvasse-match-army-hint", text: /locked in/
    assert_select "button.cyvasse-ready[aria-describedby=cyvasse-match-army-hint]"
  end

  test "the fallen card arrives hidden, with both graveyards" do
    render partial: "games/fallen_card", locals: { board: "cyvasse-match", them: "brienne" }

    assert_select ".card[hidden][data-cyvasse-match-target=fallen]" do
      assert_select "[data-cyvasse-match-target=graveyard][data-team='1']"
      assert_select "[data-cyvasse-match-target=graveyard][data-team='0']"
      assert_select "h2", text: "brienne's fallen"
    end
  end
end
