require "test_helper"

# [component] The one-line status My games prints for each match, from each
# player's side.
class MatchesHelperTest < ActionView::TestCase
  include MatchPlay

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
  end

  test "a challenge reads differently to each side" do
    match = Match.challenge!(@home, "brienne")
    assert_equal "challenge sent, awaiting brienne", match_summary(match, @home)
    assert_equal "arya challenged you", match_summary(match, @away)
  end

  test "setup and play say whose move it is" do
    match = Match.challenge!(@home, "brienne")
    match.accept!(@away)
    match.set_up!(@away, away_lineup)
    assert_equal "your army is in; arya is setting up", match_summary(match.reload, @away)
    assert_equal "set up your army", match_summary(match, @home)

    match.set_up!(@home, home_lineup)
    assert_match(/\Aturn 1, your move · due 7 days from now\z/, match_summary(match.reload, @home))
    assert_match(/\Aturn 1, arya to move/, match_summary(match, @away))
  end

  test "a finished match says who won and how" do
    match = started_match(@home, @away)
    match.resign!(@home)
    assert_equal "lost (resigned) at turn 1", match_summary(match.reload, @home)
    assert_equal "won (resigned) at turn 1", match_summary(match, @away)

    expired = Match.challenge!(@home, "brienne")
    Match.expire_stale!(now: 8.days.from_now)
    assert_equal "expired unplayed", match_summary(expired.reload, @away)
  end
end
