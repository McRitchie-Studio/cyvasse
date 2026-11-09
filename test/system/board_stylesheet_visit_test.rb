require "application_system_test_case"

# [e2e] A Turbo visit onto a board brings the board's stylesheet with it.
# game.css is linked from the board pages only, marked
# data-turbo-track=dynamic (task cyvasse-game-over-spec-race), so a page
# without it (here /rules) has no board styles until Turbo adds the sheet on
# the way in. Turbo swapping the body is not enough: the sheet must load and
# style the board (task cyvasse-board-visit-polish). The match board's visit
# (Play Now, then the computer) is checked in game_over_sign_in_test.rb.
class BoardStylesheetVisitTest < ApplicationSystemTestCase
  test "following a link onto /play is a Turbo visit that styles the board" do
    visit rules_path
    assert_no_selector "link[rel=stylesheet][href*='/assets/game-']", visible: :all
    stamp_document

    click_link "play the computer", match: :first
    assert_selector "[data-controller=cyvasse-game] svg.cyvasse-board"
    assert_same_document "the board loaded a fresh page; Turbo should render it"
    assert_selector "head link[rel=stylesheet][href*='/assets/game-'][data-turbo-track=dynamic]", visible: :all
    assert_board_stylesheet_applied
  end
end
