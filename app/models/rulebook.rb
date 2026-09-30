# The Cyvasse rulebook's reference data: each unit's attributes, grouped by
# class, and the April 2015 rule changes. The prose lives in the /rules view;
# this holds only what the view iterates.
#
# Ported from the legacy app (amcritchie/Cyvasse, app/models/units/*.rb and
# app/controllers/home_controller.rb#rules), whose stats already include the
# April 14, 2015 changes; the September 29, 2026 changes are applied on top. A reference card, not the game's source of truth:
# the engine (epic piece 4) owns the rules it enforces.
module Rulebook
  # movement and strength are strings where the original printed words
  # ("3 + 2", "Immovable"); range is nil for a unit that does not shoot.
  Unit = Data.define(:piece, :movement, :strength, :range, :trumps) do
    def name = piece.name
    def slug = piece.slug

    # A cavalry unit's two jumps, [first, second], read from its "3 + 2"
    # movement; nil for every other unit.
    def jumps
      movement.match(/\A(\d+) \+ (\d+)\z/)&.captures&.map(&:to_i)
    end

    # The Pieces this unit trumps, in rulebook order, so the unit card can
    # draw each one's art; empty when it trumps nothing.
    def trumped_pieces
      trumps.map { |name| Piece.all.find { _1.name == name } || raise(KeyError, "no piece named #{name}") }
    end
  end

  UnitClass = Data.define(:name, :units)

  def self.unit(slug, movement:, strength:, range: nil, trumps: [])
    piece = Piece.all.find { |p| p.slug == slug } || raise(KeyError, "no piece #{slug}")
    Unit.new(piece:, movement: movement.to_s, strength: strength.to_s, range:, trumps: trumps.freeze)
  end
  private_class_method :unit

  # Every cavalry unit's second jump reaches 2 hexes, whatever its first
  # (legalActions in app/javascript/cyvasse/rules.js).
  CAVALRY_SECOND_JUMP = 2

  CLASSES = [
    UnitClass.new(name: "Vanguard", units: [
      unit("rabble", movement: 3, strength: 1),
      unit("spearman", movement: 2, strength: 2, trumps: [ "Light Horse" ]),
      unit("elephant", movement: 2, strength: 4)
    ]),
    UnitClass.new(name: "Cavalry", units: [
      unit("lighthorse", movement: "3 + #{CAVALRY_SECOND_JUMP}", strength: 2),
      unit("heavyhorse", movement: "2 + #{CAVALRY_SECOND_JUMP}", strength: 3)
    ]),
    UnitClass.new(name: "Range", units: [
      unit("crossbowman", movement: 1, strength: 2, range: 2, trumps: [ "Elephant" ]),
      unit("catapult", movement: 2, strength: 3, range: 3, trumps: [ "Dragon" ]),
      unit("trebuchet", movement: 0, strength: 1, range: 4, trumps: [ "Dragon", "Spearman", "Light Horse" ])
    ]),
    UnitClass.new(name: "Unique", units: [
      unit("dragon", movement: "Moves in a straight line", strength: 5),
      unit("king", movement: 2, strength: 2, trumps: [ "Dragon" ]),
      unit("mountain", movement: "Immovable", strength: "Impassable")
    ])
  ].freeze

  # Alex's rule changes of September 29, 2026, to help the game play. The
  # engine enforces them (app/javascript/cyvasse/units.js and its Ruby mirror).
  CHANGES_2026 = [
    "Trebuchet range rose from 3 to 4. Mountains still block its shots.",
    "Trebuchets now trump Spearmen and Light Horse, so neither can take a Trebuchet. They still cannot take the King.",
    "Kings now trump Dragons: a Dragon within the King's move can be taken.",
    "Elephants now move 2."
  ].freeze

  # The rule changes of April 14, 2015 (legacy home/new_rules.html.erb).
  CHANGES_2015 = [
    "Spearmen no longer trump Heavy Horse.",
    "Catapult strength dropped from 4 to 3.",
    "Trebuchets can no longer move.",
    "Crossbowmen now trump Elephants.",
    "Catapults now trump Dragons."
  ].freeze

  UNITS = CLASSES.flat_map(&:units).index_by(&:slug).freeze

  def self.classes
    CLASSES
  end

  def self.fetch(slug)
    UNITS.fetch(slug)
  end

  def self.class_of(unit)
    CLASSES.find { |unit_class| unit_class.units.include?(unit) }.name
  end

  # The army each player sets up, counted from the engine's own list
  # (CyvasseRules::Units::ARMY, pinned to units.js) so the page cannot drift
  # from it: 19 pieces, 17 of them units of 10 kinds, and 2 mountains.
  def self.army_size = CyvasseRules::Units::ARMY.size
  def self.mountain_count = CyvasseRules::Units::ARMY.count("mountain")
  def self.army_unit_count = army_size - mountain_count
  def self.unit_kind_count = (CyvasseRules::Units::ARMY.uniq - [ "mountain" ]).size
end
