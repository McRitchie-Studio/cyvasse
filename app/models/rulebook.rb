# The Cyvasse rulebook's reference data: each unit's attributes, grouped by
# class, and the April 2015 rule changes. The prose lives in the /rules view;
# this holds only what the view iterates.
#
# Ported from the legacy app (amcritchie/Cyvasse, app/models/units/*.rb and
# app/controllers/home_controller.rb#rules), whose stats already include the
# April 14, 2015 changes. A reference card, not the game's source of truth:
# the engine (epic piece 4) owns the rules it enforces.
module Rulebook
  # movement and strength are strings where the original printed words
  # ("3 + 2", "Immovable"); range is nil for a unit that does not shoot.
  Unit = Data.define(:piece, :movement, :strength, :range, :trumps) do
    def name = piece.name
    def slug = piece.slug
  end

  UnitClass = Data.define(:name, :units)

  def self.unit(slug, movement:, strength:, range: nil, trumps: [])
    piece = Piece.all.find { |p| p.slug == slug } || raise(KeyError, "no piece #{slug}")
    Unit.new(piece:, movement: movement.to_s, strength: strength.to_s, range:, trumps: trumps.freeze)
  end
  private_class_method :unit

  CLASSES = [
    UnitClass.new(name: "Vanguard", units: [
      unit("rabble", movement: 3, strength: 1),
      unit("spearman", movement: 2, strength: 2, trumps: [ "Light Horse" ]),
      unit("elephant", movement: 3, strength: 4)
    ]),
    UnitClass.new(name: "Cavalry", units: [
      unit("lighthorse", movement: "3 + 2", strength: 2),
      unit("heavyhorse", movement: "2 + 2", strength: 3)
    ]),
    UnitClass.new(name: "Range", units: [
      unit("crossbowman", movement: 1, strength: 2, range: 2, trumps: [ "Elephant" ]),
      unit("catapult", movement: 2, strength: 3, range: 3, trumps: [ "Dragon" ]),
      unit("trebuchet", movement: 0, strength: 1, range: 3, trumps: [ "Dragon" ])
    ]),
    UnitClass.new(name: "Unique", units: [
      unit("dragon", movement: "Moves in a straight line", strength: 5),
      unit("king", movement: 2, strength: 2),
      unit("mountain", movement: "Immovable", strength: "Impassable")
    ])
  ].freeze

  # The rule changes of April 14, 2015 (legacy home/new_rules.html.erb).
  CHANGES_2015 = [
    "Spearmen no longer trump Heavy Horse.",
    "Catapult strength dropped from 4 to 3.",
    "Trebuchets can no longer move.",
    "Crossbowmen now trump Elephants.",
    "Catapults now trump Dragons."
  ].freeze

  def self.classes
    CLASSES
  end

  # "Light Horse", "Elephant and Dragon", "Rabble, Spearman and Elephant"; an
  # em dash when the unit trumps nothing (the original printed "--").
  def self.trump_list(unit)
    return "—" if unit.trumps.empty?

    unit.trumps.to_sentence(two_words_connector: " and ", last_word_connector: " and ")
  end
end
