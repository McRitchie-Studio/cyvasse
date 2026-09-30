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
  # ("4 + 1", "Immovable"); range is nil for a unit that does not shoot.
  Unit = Data.define(:piece, :movement, :strength, :range, :trumps) do
    def name = piece.name
    def slug = piece.slug

    # A cavalry unit's two jumps, [first, second], read from its "4 + 1"
    # movement; nil for every other unit. Each horse has its own second jump.
    def jumps
      movement.match(/\A(\d+) \+ (\d+)\z/)&.captures&.map(&:to_i)
    end
  end

  UnitClass = Data.define(:name, :units)

  def self.unit(slug, movement:, strength:, range: nil, trumps: [])
    piece = Piece.all.find { |p| p.slug == slug } || raise(KeyError, "no piece #{slug}")
    Unit.new(piece:, movement: movement.to_s, strength: strength.to_s, range:, trumps: trumps.freeze)
  end
  private_class_method :unit

  CLASSES = [
    UnitClass.new(name: "Vanguard", units: [
      unit("rabble", movement: 3, strength: 1, trumps: [ "King" ]),
      unit("spearman", movement: 2, strength: 3, trumps: [ "Elephant" ]),
      unit("elephant", movement: 2, strength: 4)
    ]),
    UnitClass.new(name: "Cavalry", units: [
      unit("lighthorse", movement: "4 + 1", strength: 2),
      unit("heavyhorse", movement: "3 + 1", strength: 3)
    ]),
    UnitClass.new(name: "Range", units: [
      unit("crossbowman", movement: 1, strength: 2, range: 2),
      unit("catapult", movement: 1, strength: 3, range: 3, trumps: [ "Dragon" ]),
      unit("trebuchet", movement: 0, strength: 1, range: 4, trumps: [ "Dragon" ])
    ]),
    UnitClass.new(name: "Unique", units: [
      unit("dragon", movement: "Moves in a straight line", strength: 5),
      unit("king", movement: 2, strength: 2, trumps: [ "Dragon" ]),
      unit("mountain", movement: "Immovable", strength: "Impassable")
    ])
  ].freeze

  # The Strength a Range unit defends at, whatever it attacks with: any unit
  # can take one (Alex, September 29, 2026). Every other unit defends at its
  # Strength. The engine's defence column (app/javascript/cyvasse/units.js).
  RANGE_DEFENCE = 1

  # Alex's rule changes of September 29, 2026, to help the game play. The
  # engine enforces them (app/javascript/cyvasse/units.js and its Ruby mirror).
  # The first four came in the morning; the rest are "a new set of stats"
  # that evening (task cyvasse-stats-and-trumps-v3), which also took back the
  # Trebuchet's Spearman and Light Horse trumps.
  CHANGES_2026 = [
    "Trebuchet range rose from 3 to 4. Mountains still block its shots.",
    "Kings now trump Dragons: a Dragon within the King's move can be taken.",
    "Elephants now move 2.",
    "Trumps now work on offense only: a unit takes a unit it trumps when it attacks, but a trump never protects the " \
    "unit that holds it. A Trebuchet can take a Dragon, and a Dragon can still take a Trebuchet.",
    "Strength is every unit's attack: Rabble 1, Trebuchet 1, King 2, Light Horse 2, Crossbowman 2, Spearman 3, " \
    "Heavy Horse 3, Catapult 3, Elephant 4, Dragon 5. Range units still defend at 1, so any unit can take one.",
    "New trumps: Rabble trump the King, and Spearmen trump Elephants instead of Light Horse. Trebuchets trump only " \
    "Dragons, and Crossbowmen trump nothing.",
    "Light Horse now move 4 then 1, and Heavy Horse 3 then 1 (were 3 then 2, and 2 then 2).",
    "Catapults now move 1."
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

  # "Light Horse", "Elephant and Dragon", "Rabble, Spearman and Elephant"; an
  # em dash when the unit trumps nothing (the original printed "--").
  def self.trump_list(unit)
    return "—" if unit.trumps.empty?

    unit.trumps.to_sentence(two_words_connector: " and ", last_word_connector: " and ")
  end
end
