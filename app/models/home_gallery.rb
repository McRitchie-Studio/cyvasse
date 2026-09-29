# The front door's background: one action shot per piece, shown in turn.
#
# Each shot is a real board state from /play, staged so its piece is the hero
# (a dragon mid-swoop, a trebuchet's range lit, a light horse between its two
# jumps) and captured in the default vector skin by
# test/capture/home_gallery_capture.rb (`bin/rails cyvasse:capture_home_gallery`
# re-runs it). Each piece has two crops under app/assets/images/backgrounds/home:
# <slug>.webp for a wide screen and <slug>-mobile.webp, a portrait crop for a
# phone.
#
# A catalogue, not a record, like Piece.
class HomeGallery
  DIRECTORY = "backgrounds/home".freeze
  # How long each slide holds before the next fades in.
  INTERVAL_MS = 7000

  Slide = Data.define(:piece) do
    def slug = piece.slug
    def caption = "The #{piece.name}"
    def desktop_image = "#{DIRECTORY}/#{slug}.webp"
    def mobile_image = "#{DIRECTORY}/#{slug}-mobile.webp"
  end

  SLIDES = Piece.all.map { |piece| Slide.new(piece:) }.freeze

  # Every slide, starting from a random one and keeping the order after it,
  # so each visit opens on a different piece. `random` is injectable for tests.
  def self.slides(random: Random)
    SLIDES.rotate(random.rand(SLIDES.size))
  end
end
