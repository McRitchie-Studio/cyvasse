# The eleven Cyvasse pieces and where each one's art lives.
#
# Every piece is drawn twice, in the two skins the legacy app shipped
# (amcritchie/Cyvasse): the pencil drawings (app/assets/images/pieces/*.png
# there) and the coloured vector art (public/images/svgs/*.svg there). Both
# now live under app/assets/images/pieces/<skin>/<slug>.<ext> and are served
# through Propshaft, so a caller resolves them with image_path/image_tag.
#
# A catalogue, not a record: the game engine (epic piece 4) reads the lineup
# and the skin switcher (piece 5) reads SKINS. Neither is persisted.
class Piece
  SKINS = { pencil: "png", vector: "svg" }.freeze

  attr_reader :slug, :name

  def initialize(slug:, name:)
    @slug = slug
    @name = name
    freeze
  end

  # The legacy lineup order: the king first, the mountain (terrain) last.
  ALL = [
    new(slug: "king", name: "King"),
    new(slug: "rabble", name: "Rabble"),
    new(slug: "spearman", name: "Spearman"),
    new(slug: "crossbowman", name: "Crossbowman"),
    new(slug: "lighthorse", name: "Light Horse"),
    new(slug: "heavyhorse", name: "Heavy Horse"),
    new(slug: "elephant", name: "Elephant"),
    new(slug: "catapult", name: "Catapult"),
    new(slug: "trebuchet", name: "Trebuchet"),
    new(slug: "dragon", name: "Dragon"),
    new(slug: "mountain", name: "Mountain")
  ].freeze

  def self.all
    ALL
  end

  # Logical asset path for one skin, e.g. "pieces/vector/king.svg". Raises
  # KeyError on an unknown skin rather than building a path that 404s.
  def image(skin)
    "pieces/#{skin}/#{slug}.#{SKINS.fetch(skin.to_sym)}"
  end
end
