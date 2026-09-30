require "test_helper"

# [unit] HomeGallery: one slide per piece, each with both crops on disk at 1x
# and 2x under their size caps, started from a random piece with the order kept.
class HomeGalleryTest < ActiveSupport::TestCase
  IMAGES = Rails.root.join("app/assets/images")

  test "one slide per piece, captioned with its name" do
    assert_equal Piece.all.map(&:slug), HomeGallery::SLIDES.map(&:slug)
    assert_equal "The Light Horse", HomeGallery::SLIDES.find { _1.slug == "lighthorse" }.caption
  end

  test "every slide has a wide and a portrait crop on disk, each at 1x and 2x, under its cap" do
    HomeGallery::SLIDES.each do |slide|
      (HomeGallery::WIDE + HomeGallery::PORTRAIT).each do |size|
        image = slide.image(size)
        path = IMAGES.join(image)
        assert path.file?, image
        assert_equal "RIFF", File.binread(path, 4), "#{image} is a WebP"
        assert_equal "WEBP", File.binread(path, 4, 8), "#{image} is a WebP"
        assert_operator File.size(path), :<=, size.max_bytes, image
        # The srcset's width descriptor is the file's real width; the height
        # is the crop's, give or take Chrome's rounding of the clip.
        width, height = webp_size(path)
        assert_equal size.width, width, "#{image} width"
        assert_in_delta size.height, height, 8, "#{image} height"
      end
    end
    expected = HomeGallery::SLIDES.flat_map(&:images).map { File.basename(_1) }
    assert_equal expected.sort, Dir.children(IMAGES.join(HomeGallery::DIRECTORY)).sort, "no stray files"
  end

  test "the 2x crops are twice the 1x, and at most 150 KB and 250 KB" do
    [ HomeGallery::WIDE, HomeGallery::PORTRAIT ].each do |one, two|
      assert_equal [ one.width * 2, one.height * 2 ], [ two.width, two.height ]
      assert_equal 150 * 1024, one.max_bytes
      assert_equal 250 * 1024, two.max_bytes
    end
    slide = HomeGallery::SLIDES.first
    assert_equal [ [ "backgrounds/home/#{slide.slug}.webp", 1800 ], [ "backgrounds/home/#{slide.slug}-2x.webp", 3600 ] ], slide.wide_images
    assert_equal [ [ "backgrounds/home/#{slide.slug}-mobile.webp", 720 ], [ "backgrounds/home/#{slide.slug}-mobile-2x.webp", 1440 ] ], slide.portrait_images
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

  private

  # [width, height] of a lossy (VP8) or extended (VP8X) WebP, from its header.
  def webp_size(path)
    head = File.binread(path, 30)
    case head[12, 4]
    when "VP8 " then head[26, 4].unpack("vv").map { _1 & 0x3fff }
    when "VP8X" then [ head[24, 3], head[27, 3] ].map { (_1 + "\0").unpack1("V") + 1 }
    else flunk "#{path}: an unexpected #{head[12, 4].inspect} chunk"
    end
  end
end
