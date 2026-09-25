require "test_helper"

# [component] /pieces renders both skins of every piece, side by side.
class PiecesPageTest < ActionDispatch::IntegrationTest
  test "renders publicly with 22 piece images, each with alt text" do
    get pieces_path

    assert_response :success
    assert_select "h1", text: "The Pieces"
    assert_select ".piece-tile img", count: 22
    assert_select ".piece-tile img:not([alt])", count: 0
    assert_select ".piece-tile img[alt='']", count: 0
  end

  test "each piece shows the pencil tile first and the vector tile second" do
    get pieces_path

    Piece.all.each do |piece|
      assert_select "section##{piece.slug}" do
        assert_select "h2", text: piece.name
        assert_select "figure.piece-tile", count: 2
        assert_select "figure.piece-tile:nth-of-type(1)[data-skin=pencil] img[alt=?]", "#{piece.name}, pencil skin"
        assert_select "figure.piece-tile:nth-of-type(2)[data-skin=vector] img[alt=?]", "#{piece.name}, vector skin"
      end
    end
  end

  test "image sources point at the digested pencil PNG and vector SVG" do
    get pieces_path

    sources = css_select(".piece-tile img").map { |img| img["src"] }
    assert_equal 11, sources.count { |src| src.match?(%r{/assets/pieces/pencil/\w+-\w+\.png\z}) }
    assert_equal 11, sources.count { |src| src.match?(%r{/assets/pieces/vector/\w+-\w+\.svg\z}) }
  end
end
