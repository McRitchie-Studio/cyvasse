require "test_helper"

# [component] /play renders the board shell publicly and hands the engine the
# chosen skin's piece art. The board itself is drawn by the browser; the
# rules are unit-tested in test/javascript and played end to end in
# test/system/play_against_computer_test.rb.
class GamePageTest < ActionDispatch::IntegrationTest
  def images
    JSON.parse(css_select("[data-controller=cyvasse-game]").first["data-cyvasse-game-images-value"])
  end

  test "renders for a signed-out visitor" do
    get play_path

    assert_response :success
    assert_select "h1", text: "Play Cyvasse"
    assert_select "[data-controller=cyvasse-game] svg.cyvasse-board[data-cyvasse-game-target=board]"
    assert_select "button.cyvasse-smart", text: "✨ Smart Setup"
    assert_select "button[disabled]", text: "Ready"
  end

  test "the threat switches arrive hidden: setup comes first and the board shows them in play" do
    get play_path

    assert_select ".cyvasse-board-bar .cyvasse-threat-toggles[hidden] input[type=checkbox][data-cyvasse-game-target=threatToggle]", 2
  end

  # The picker loads onto the board, and follows it back: the board announces
  # every change to the army on the window (cyvasse-game:lineup), so the
  # picker can name the opening Smart Setup placed (task
  # cyvasse-smart-setup-king-safety: it said "Iron Corner" whatever stood there).
  test "offers the opening picker to every player, wired to the board both ways" do
    get play_path

    picker = "[data-controller=cyvasse-openings]" \
      "[data-action~='cyvasse-openings:load->cyvasse-game#loadLineup']" \
      "[data-action~='cyvasse-game:lineup@window->cyvasse-openings#reflect']"
    assert_select picker do
      assert_select "select[data-cyvasse-openings-target=select]"
      assert_select "button[data-action='cyvasse-openings#load']", text: "Load opening"
    end
  end

  test "draws the vector skin by default, one image per piece" do
    get play_path

    assert_select "[data-controller=cyvasse-game][data-cyvasse-game-skin-value=vector][data-skin=vector]"
    assert_equal Piece.all.map(&:slug).sort, images.keys.sort
    images.each do |slug, src|
      assert_match %r{\A/assets/pieces/vector/#{slug}-\w+\.svg\z}, src
    end
  end

  test "the skin is one parameter: ?skin=pencil draws the pencil art" do
    get play_path(skin: "pencil")

    assert_select "[data-cyvasse-game-skin-value=pencil][data-skin=pencil]"
    assert(images.values.all? { |src| src.match?(%r{\A/assets/pieces/pencil/\w+-\w+\.png\z}) })
  end

  test "an unknown skin falls back to vector rather than a broken path" do
    get play_path(skin: "chalk")

    assert_select "[data-cyvasse-game-skin-value=vector]"
    assert(images.values.all? { |src| src.include?("/pieces/vector/") })
  end

  test "the importmap serves the game engine modules" do
    get play_path

    %w[cyvasse/game cyvasse/rules cyvasse/board cyvasse/units cyvasse/ai cyvasse/setups cyvasse/potential_range].each do |mod|
      assert_includes response.body, %("#{mod}": "/assets/#{mod}-), "#{mod} is not pinned"
    end
    assert_select "link[rel=stylesheet][href^='/assets/game-']"
  end

  # The computer game is still reached through Play Now's fallback; the front
  # door's second button is Rules now.
  test "the front door offers the rules, not a separate computer button" do
    get root_path

    assert_select "a[href=?]", rules_path, text: "Rules"
    assert_select "section.home-hero a[href=?]", play_path, 0
  end
end
