require "test_helper"

# [unit] HomeGallery: one slide per piece, each with both crops on disk under
# the size cap, started from a random piece with the order kept.
class HomeGalleryTest < ActiveSupport::TestCase
  IMAGES = Rails.root.join("app/assets/images")

  test "one slide per piece, captioned with its name" do
    assert_equal Piece.all.map(&:slug), HomeGallery::SLIDES.map(&:slug)
    assert_equal "The Light Horse", HomeGallery::SLIDES.find { _1.slug == "lighthorse" }.caption
  end

  test "every slide has a wide and a portrait crop on disk, each under 150 KB" do
    HomeGallery::SLIDES.each do |slide|
      [ slide.desktop_image, slide.mobile_image ].each do |image|
        path = IMAGES.join(image)
        assert path.file?, image
        assert_equal "RIFF", File.binread(path, 4), "#{image} is a WebP"
        assert_equal "WEBP", File.binread(path, 4, 8), "#{image} is a WebP"
        assert_operator File.size(path), :<=, 150.kilobytes, image
      end
    end
    expected = HomeGallery::SLIDES.flat_map { [ "#{_1.slug}.webp", "#{_1.slug}-mobile.webp" ] }
    assert_equal expected.sort, Dir.children(IMAGES.join(HomeGallery::DIRECTORY)).sort, "no stray files"
  end

  test "the capture script stages a scene for every slide" do
    scenes = Rails.root.join("test/capture/home_gallery_capture.rb").read
    HomeGallery::SLIDES.each { |slide| assert_match(/^    "#{slide.slug}" => \{/, scenes, slide.slug) }
  end

  test "slides start from a random piece and keep the order after it" do
    starts = 40.times.map { HomeGallery.slides.first.slug }.uniq
    assert_operator starts.size, :>, 1, "the start varies"

    slides = HomeGallery.slides(random: Random.new(7))
    offset = HomeGallery::SLIDES.index(slides.first)
    assert_equal HomeGallery::SLIDES.rotate(offset), slides
    assert_equal HomeGallery::SLIDES.size, slides.size
  end
end
