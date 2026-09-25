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
    assert_select "button", text: "Random Setup"
    assert_select "button[hidden]", text: "Start Game"
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

  test "the front door offers a game against the computer" do
    get root_path

    assert_select "a[href=?]", play_path, text: "Play the computer"
  end
end
