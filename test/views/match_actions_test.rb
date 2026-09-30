require "test_helper"

# [component] The match page's links and forfeit (matches/_actions), rendered
# alone: "Forfeit match" is a danger-outline button on its own row, apart from
# the links, never the green fill of a Play button, and it still asks first;
# a finished match has no forfeit. The turn banner's slot (games/_banner)
# sits outside the board.
class MatchActionsTest < ActionView::TestCase
  include MatchPlay

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  test "an in-progress match's forfeit is a danger outline on its own row, and asks first" do
    match = started_match(@home, @away)
    render partial: "matches/actions", locals: { match:, opponent_name: "brienne", can_accept: false }

    assert_select ".match-actions > .match-links", 1 do
      assert_select "a", text: "← My games"
      assert_select "a", text: "How to play"
      assert_select "button", text: "Forfeit match", count: 0
    end
    assert_select ".match-actions > .match-forfeit[data-forfeit=play]", 1 do
      assert_select "form[action=?][data-turbo-confirm=?]", resign_match_path(match), "Forfeit this match? brienne wins." do
        forfeit = assert_select("button", text: "Forfeit match").first
        classes = forfeit["class"].split
        assert_includes classes, "match-forfeit-button"
        assert_empty classes & %w[btn-primary btn-secondary btn-success btn-danger], "no filled 'go' style: #{classes.inspect}"
      end
    end
  end

  test "a pregame match offers the call-off forfeit too, in the same danger style" do
    match = Match.challenge!(@home, "brienne")
    render partial: "matches/actions", locals: { match:, opponent_name: "brienne", can_accept: false }

    assert_select ".match-forfeit[data-forfeit=pregame] form[action=?][data-turbo-confirm]", match_path(match) do
      assert_select "button.match-forfeit-button:not(.btn-secondary)", "Forfeit match"
    end
  end

  test "a finished match renders no forfeit" do
    match = started_match(@home, @away)
    match.resign!(@home)
    render partial: "matches/actions", locals: { match: match.reload, opponent_name: "brienne", can_accept: false }

    assert_select ".match-forfeit", 0
    assert_no_match(/Forfeit/, rendered)
  end

  test "the forfeit stylesheet is a danger outline, not a fill" do
    css = Rails.root.join("app/assets/stylesheets/game.css").read
    rule = css[/^\.match-forfeit-button \{[^}]*\}/m]
    assert rule, "game.css styles .match-forfeit-button"
    assert_match(/background: transparent;/, rule)
    assert_match(/border: 1px solid [^;]*--color-danger/, rule)
    assert_match(/color: var\(--color-danger-ink/, rule)
  end

  test "the turn banner renders in its own slot, not over the board" do
    render partial: "games/banner", locals: { board: "cyvasse-match" }

    assert_select ".cyvasse-banner-slot > .cyvasse-banner[hidden][data-cyvasse-match-target=banner]", 1
    assert_select "svg", 0
  end
end
