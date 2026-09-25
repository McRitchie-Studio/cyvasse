require "test_helper"

class PieceTest < ActiveSupport::TestCase
  test "the lineup is the eleven legacy pieces, each slug once" do
    slugs = Piece.all.map(&:slug)

    assert_equal 11, slugs.size
    assert_equal slugs.uniq, slugs
    assert_equal %w[catapult crossbowman dragon elephant heavyhorse king lighthorse mountain rabble spearman trebuchet],
                 slugs.sort
  end

  test "image builds the skin's logical asset path" do
    king = Piece.all.first

    assert_equal "pieces/pencil/king.png", king.image(:pencil)
    assert_equal "pieces/vector/king.svg", king.image("vector")
  end

  test "an unknown skin raises instead of building a path that 404s" do
    assert_raises(KeyError) { Piece.all.first.image(:iron) }
  end

  # Every piece in every skin resolves through Propshaft, so a missing or
  # misnamed file fails here rather than as a broken image on the page.
  test "every piece's art exists in both skins" do
    Piece.all.each do |piece|
      Piece::SKINS.each_key do |skin|
        asset = Rails.application.assets.load_path.find(piece.image(skin))
        assert asset, "missing #{piece.image(skin)}"
      end
    end
  end
end
