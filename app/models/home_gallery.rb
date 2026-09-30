# The front door's background: one action shot per piece, shown in turn.
#
# Each shot is a real board state from /play, staged so its piece is the hero
# (a dragon mid-swoop, a trebuchet's range lit, a light horse between its two
# jumps) and captured in the default vector skin by
# test/capture/home_gallery_capture.rb (`bin/rails cyvasse:capture_home_gallery`
# re-runs it). Each piece has two crops under app/assets/images/backgrounds/home,
# each drawn at two sizes so a 2x screen gets sharp art: <slug>.webp (1800 px)
# and <slug>-2x.webp (3600 px) for a wide screen, and <slug>-mobile.webp
# (720 px) and <slug>-mobile-2x.webp (1440 px), a portrait crop for a phone.
# The page offers each pair as a srcset with width descriptors, so the browser
# picks one per slide.
#
# A catalogue, not a record, like Piece.
class HomeGallery
  DIRECTORY = "backgrounds/home".freeze
  # How long each slide holds before the next fades in.
  INTERVAL_MS = 7000

  # One drawing of a crop: the file-name suffix, its pixel size, and the byte
  # cap the capture keeps it under. The 1x file of each crop is first.
  Size = Data.define(:suffix, :width, :height, :max_bytes)
  WIDE = [
    Size.new(suffix: "", width: 1800, height: 900, max_bytes: 150 * 1024),
    Size.new(suffix: "-2x", width: 3600, height: 1800, max_bytes: 250 * 1024)
  ].freeze
  PORTRAIT = [
    Size.new(suffix: "-mobile", width: 720, height: 1152, max_bytes: 150 * 1024),
    Size.new(suffix: "-mobile-2x", width: 1440, height: 2304, max_bytes: 250 * 1024)
  ].freeze
  # The art covers the hero edge to edge, so each crop is drawn about the
  # viewport's width.
  SIZES = "100vw".freeze

  Slide = Data.define(:piece) do
    def slug = piece.slug
    def caption = "The #{piece.name}"
    def image(size) = "#{DIRECTORY}/#{slug}#{size.suffix}.webp"
    # The 1x files, the <img>'s src and the fallback.
    def desktop_image = image(WIDE.first)
    def mobile_image = image(PORTRAIT.first)
    # [[logical path, pixel width], ...] for a srcset, 1x first.
    def wide_images = WIDE.map { [ image(_1), _1.width ] }
    def portrait_images = PORTRAIT.map { [ image(_1), _1.width ] }
    def images = (WIDE + PORTRAIT).map { image(_1) }
  end

  SLIDES = Piece.all.map { |piece| Slide.new(piece:) }.freeze

  # Every slide, starting from a random one and keeping the order after it,
  # so each visit opens on a different piece. `random` is injectable for tests.
  def self.slides(random: Random)
    SLIDES.rotate(random.rand(SLIDES.size))
  end
end
