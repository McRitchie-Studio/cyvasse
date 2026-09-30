require "test_helper"

# [component] The phone setup dock's container (task cyvasse-phone-setup-dock),
# on both setup pages: the army card sits first in the setup controls
# (.cyvasse-setup-controls), which game.css docks as a sheet under the board
# on a phone, with the setup clock's copy beside the count. The openings and
# saved lineups stay outside the card, in the page's flow.
class SetupDockMarkupTest < ActionDispatch::IntegrationTest
  include MatchPlay

  test "/play renders the dock container with the army card first" do
    get play_path

    assert_dock "cyvasse-game"
  end

  test "a live match's setup renders the dock container with the army card first" do
    arya = make_player("arya")
    log_in_as(arya)
    get match_path(Match.start_live!(arya, computer: true, rng: Random.new(4)))

    assert_dock "cyvasse-match"
  end

  private

  def assert_dock(board)
    assert_select "section.cyvasse-game[data-controller=#{board}] .cyvasse-setup-controls[data-#{board}-target=setupControls]", 1 do
      assert_select "> .cyvasse-army:first-child[data-#{board}-target=army]", 1 do
        assert_select ".cyvasse-dock[data-#{board}-target=dock]", 1
        assert_select "button.cyvasse-smart", 1
        assert_select "button.cyvasse-ready", 1
        assert_select ".cyvasse-army-clock[hidden][aria-hidden=true][data-#{board}-target=armyClock]", 1
      end
      assert_select "> .card:not(.cyvasse-army) [data-controller=cyvasse-openings]", 1
    end
  end
end
