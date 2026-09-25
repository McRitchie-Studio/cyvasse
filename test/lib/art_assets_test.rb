require "test_helper"

# The legacy art imported from amcritchie/Cyvasse (epic cyvasse-revival piece 3)
# and the favicon drawn from it.
class ArtAssetsTest < ActiveSupport::TestCase
  IMAGES = Rails.root.join("app/assets/images")

  EXPECTED = {
    "backgrounds" => %w[cyvasse_404_background.png cyvasse_about_background.png cyvasse_background.png
                        cyvasse_message_background.png cyvasse_rules_background.png],
    "title" => %w[cyvasse_title.png cyvasse_title2.png],
    "tutorial" => %w[cavalry.png dragon.png range.png trump.png],
    "thanks" => %w[aarongray.jpg alexmcritchie.jpg bobbyblackstock.jpeg bobbywilson.jpg gschool.jpg
                   jefftaggart.jpeg seansmith.jpeg zachklabunde.jpeg]
  }.freeze

  test "backgrounds, title, tutorial and thanks images are all imported" do
    EXPECTED.each do |dir, files|
      assert_equal files.sort, Dir.children(IMAGES.join(dir)).sort, "app/assets/images/#{dir}"
    end
    assert IMAGES.join("hex.svg").file?, "hex.svg"
  end

  # The originals ran to 600 KB a file; the import compressed them. This keeps a
  # later drop-in of an uncompressed original from slipping through.
  test "no imported raster is larger than 250 KB" do
    oversized = Dir[IMAGES.join("**/*.{png,jpg,jpeg}")].select { |path| File.size(path) > 250.kilobytes }

    assert_empty oversized.map { |path| path.delete_prefix("#{IMAGES}/") }
  end

  # The engine's shared head links /favicon.png; before this import it 404'd.
  test "the favicon the engine head links is a real PNG" do
    favicon = Rails.root.join("public/favicon.png")

    assert favicon.file?, "public/favicon.png"
    assert_equal "\x89PNG".b, File.binread(favicon, 4)
  end
end
