require "application_system_test_case"

# [e2e] The piece-skin switcher in a real browser (epic cyvasse-revival
# piece 5). On /play the switch redraws the game in progress without a
# reload; the choice then carries to /rules and /pieces through the cookie,
# and on /pieces the plain form post reloads the gallery in the new order.
class SkinSwitcherSystemTest < ApplicationSystemTestCase
  test "switching to pencil mid-setup keeps the game and every page follows" do
    visit play_path
    game = find("[data-controller=cyvasse-game]")
    assert_equal "vector", game["data-skin"]

    place_one_by_hand
    # Mark the page: a reload would drop this, so its survival proves the
    # switch happened in place.
    page.execute_script("window.__sameGame = true")

    within(".skin-toggle") { click_on "Pencil" }

    assert_selector "[data-controller=cyvasse-game][data-skin=pencil]"
    assert_selector ".skin-toggle button[data-skin=pencil][aria-pressed=true]"
    assert_selector ".skin-toggle button[data-skin=vector][aria-pressed=false]"
    assert_equal "pencil", page.evaluate_script("document.activeElement.dataset.skin"),
                 "keyboard focus stays on the toggle through the save"
    assert_selector ".cyvasse-dock img[src*='/pieces/pencil/']", count: 18
    assert_no_selector ".cyvasse-dock img[src*='/pieces/vector/']"
    king = find("svg.cyvasse-board g.hex[data-hex='88'][data-unit-id='1-17'] image.unit-image")
    assert_includes king[:href], "/pieces/pencil/king"
    assert page.evaluate_script("window.__sameGame === true"), "the switch reloaded the page"

    visit rules_path
    assert_selector "#units figure.piece-tile img[src*='/pieces/pencil/']", count: 11
    assert_selector ".skin-toggle button[data-skin=pencil][aria-pressed=true]"

    visit pieces_path
    assert_selector "section#king figure.piece-tile:first-of-type[data-skin=pencil]"
    within(".skin-toggle") { click_on "Vector" }
    assert_current_path pieces_path
    assert_selector "section#king figure.piece-tile:first-of-type[data-skin=vector]"

    visit play_path
    assert_selector "[data-controller=cyvasse-game][data-skin=vector]"
  end

  private

  def place_one_by_hand
    find(".cyvasse-dock .dock-unit[data-unit-id='1-17']").click
    find("svg.cyvasse-board g.hex[data-hex='88']").click
    assert_selector "svg.cyvasse-board g.hex[data-hex='88'][data-unit-id='1-17']"
    assert_selector ".cyvasse-dock .dock-unit", count: 18
  end
end
