require "application_system_test_case"

# [e2e] A picked piece is let go by clicking it again, clicking off the board,
# or clicking a hex it cannot reach; another own piece still switches the
# pick, a control beside the board keeps it, and a legal target still moves.
class ClickToDeselectTest < ApplicationSystemTestCase
  include MatchPlay

  SELECTED = "svg.cyvasse-board g.hex.is-selected".freeze
  TARGETS = "svg.cyvasse-board g.hex.is-move, svg.cyvasse-board g.hex.is-attack".freeze

  test "on /play, a picked piece is let go three ways" do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
    click_on "Random Setup"
    click_on "Ready"
    # As the sibling /play tests do: the game has started before the pace
    # drops, and a computer that moves first gets the time its paced turn takes.
    assert_selector "[data-controller=cyvasse-game][data-phase=play]"
    page.execute_script("document.querySelector('[data-controller=cyvasse-game]').dataset.cyvasseGamePaceValue = '0'")
    assert_selector "[data-controller=cyvasse-game][data-phase=play][data-offense='1'][data-holding=false]", wait: 25

    deselects_three_ways
    turn = find("[data-controller=cyvasse-game]")["data-turn"].to_i
    switches_keeps_and_moves("[data-controller=cyvasse-game]") { |node| node["data-turn"].to_i > turn }
  end

  test "in setup, a picked unit is let go three ways and placement still works" do
    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-phase=setup]"
    find(".cyvasse-dock .dock-unit[data-unit-id='1-17']").click
    hex(88).click
    assert_selector "svg.cyvasse-board g.hex[data-hex='88'][data-unit-id='1-17']"

    hex(88).click
    assert_selector "#{SELECTED}[data-hex='88']"
    hex(88).click
    assert_no_selector SELECTED

    hex(88).click
    off_board
    assert_no_selector SELECTED

    hex(88).click
    hex(10).click
    assert_no_selector SELECTED
    assert_selector "svg.cyvasse-board g.hex[data-hex='88'][data-unit-id='1-17']"

    find(".cyvasse-dock .dock-unit[data-unit-id='1-16']").click
    assert_selector ".cyvasse-dock .dock-unit[data-unit-id='1-16'][aria-pressed=true]"
    off_board
    assert_no_selector ".cyvasse-dock .dock-unit[aria-pressed=true]"

    find(".cyvasse-dock .dock-unit[data-unit-id='1-16']").click
    hex(87).click
    assert_selector "svg.cyvasse-board g.hex[data-hex='87'][data-unit-id='1-16']"
  end

  test "on a match, a picked piece is let go three ways" do
    home = make_player("arya")
    away = make_player("brienne")
    match = started_match(home, away)
    mover = match.user_to_move

    visit link_path(token: Studio::Link.create_magic_link(email: mover.email).token)
    assert_text "Signed in as #{mover.name}"
    visit match_path(match)
    board = "[data-controller=cyvasse-match]"
    assert_selector "#{board}[data-your-turn=true][data-phase=play]"
    page.execute_script("document.querySelector('#{board}').dataset.cyvasseMatchPaceValue = '0'")

    deselects_three_ways
    switches_keeps_and_moves("#{board}[data-your-turn=false]")
    assert_equal 2, match.reload.turn
  end

  private

  def hex(index) = find("svg.cyvasse-board g.hex[data-hex='#{index}']")

  def off_board = find("[role=status][aria-live=polite]", match: :first).click

  # An own unit with somewhere to go, picked; its hex.
  def pick_mover(except: nil)
    all("svg.cyvasse-board g.hex.has-unit[data-team='1']").map { |node| node["data-hex"] }.each do |index|
      next if index == except

      hex(index).click
      return index if first(TARGETS, minimum: 0, wait: 0.3)
    end
    flunk "none of our units could move"
  end

  def assert_let_go
    assert_no_selector SELECTED
    assert_no_selector TARGETS
  end

  def deselects_three_ways
    picked = pick_mover
    hex(picked).click
    assert_let_go

    hex(picked).click
    assert_selector "#{SELECTED}[data-hex='#{picked}']"
    off_board
    assert_let_go

    hex(picked).click
    assert_selector TARGETS
    unreachable = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("svg.cyvasse-board g.hex")]
        .find((g) => !g.matches(".is-move, .is-attack, .has-unit")).dataset.hex
    JS
    hex(unreachable).click
    assert_let_go
  end

  def switches_keeps_and_moves(after_move, &filter)
    first_pick = pick_mover
    second_pick = pick_mover(except: first_pick)
    assert_selector "#{SELECTED}[data-hex='#{second_pick}']"
    assert_no_selector "#{SELECTED}[data-hex='#{first_pick}']"

    find_field("Ranged threats").click
    assert_selector "#{SELECTED}[data-hex='#{second_pick}']"

    first(TARGETS).click
    # A cavalry unit's second jump keeps the turn; take it.
    first(TARGETS, minimum: 0, wait: 0.5)&.click if page.has_selector?(SELECTED, wait: 0)
    # At pace 0 the computer answers at once, so /play's passing move is the
    # turn counter moving on, not a fleeting data-offense='0'.
    assert_selector(after_move, wait: 10, &filter)
  end
end
