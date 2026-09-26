require "application_system_test_case"

# [e2e] A signed-out visitor plays a whole game against the computer, in a real
# browser, through the board's own clicks. The engine's rules are unit-tested
# in test/javascript; this proves the page boots them and a game runs to its
# end. Once both armies are on the board the controller's `pace` value is set
# to 0, so the legacy delays (the computer's 1.5 s think, the 1.8 s banners) do
# not make the test slow.
class PlayAgainstComputerTest < ApplicationSystemTestCase
  MAX_TURNS = 400

  test "a signed-out visitor sets up, starts, and plays a game to the end" do
    visit play_path
    game = find("[data-controller=cyvasse-game]")
    assert_equal "setup", game["data-phase"]
    assert_selector "svg.cyvasse-board g.hex", count: 91
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    assert_selector ".cyvasse-dock img[src*='/pieces/vector/']", count: 19

    place_one_by_hand
    click_on "Random Setup"
    assert_no_selector ".cyvasse-dock .dock-unit"
    screenshot("setup")
    click_on "Start Game"

    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='0']", count: 19
    assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='1']", count: 19
    # Both armies are counted at the legacy pace, while the opening banner is
    # still up and nobody can have moved; from here on, no delays.
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")

    turns = 0
    until game["data-phase"] == "over"
      wait_for_my_move_or_the_end(game)
      break if game["data-phase"] == "over"
      take_a_turn
      turns += 1
      screenshot("midgame") if turns == 3
      assert_operator turns, :<, MAX_TURNS, "the game should end"
    end

    assert_equal "over", game["data-phase"]
    assert_selector ".cyvasse-banner", text: /You win, at turn \d+\.|You were defeated, at turn \d+\./
    screenshot("over")
  end

  private

  # Pick the king from the dock and set it on the back row by hand.
  def place_one_by_hand
    find(".cyvasse-dock .dock-unit[data-unit-id='1-17']").click
    find("svg.cyvasse-board g.hex[data-hex='88']").click
    assert_selector "svg.cyvasse-board g.hex[data-hex='88'][data-unit-id='1-17']"
    assert_selector ".cyvasse-dock .dock-unit", count: 18
  end

  def wait_for_my_move_or_the_end(game)
    assert_selector "[data-controller=cyvasse-game][data-phase=over], [data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 15
  end

  # Select our units in turn until one has somewhere to go; take a capture if
  # one is offered, else the first move. A cavalry unit then jumps again.
  def take_a_turn
    all("svg.cyvasse-board g.hex.has-unit[data-team='1']").map { |node| node["data-hex"] }.each do |hex|
      find("svg.cyvasse-board g.hex[data-hex='#{hex}']").click
      target = first("svg.cyvasse-board g.hex.is-attack", minimum: 0, wait: 0) ||
               first("svg.cyvasse-board g.hex.is-move", minimum: 0, wait: 0)
      next unless target

      target.click
      second = first("svg.cyvasse-board g.hex.is-attack, svg.cyvasse-board g.hex.is-move", minimum: 0, wait: 0.3)
      second&.click if find("[data-controller=cyvasse-game]")["data-offense"] == "1" && game_still_playing?
      return
    end
    flunk "none of our units could move"
  end

  def game_still_playing?
    find("[data-controller=cyvasse-game]")["data-phase"] == "play"
  end

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/play-#{name}.png")) if ENV["SCREENSHOTS"]
  end
end
