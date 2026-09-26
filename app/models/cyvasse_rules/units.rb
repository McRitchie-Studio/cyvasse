module CyvasseRules
  # The eleven unit types and the nineteen-piece army: a Ruby mirror of
  # app/javascript/cyvasse/units.js, which is the source of truth. The server
  # validates every online move with these numbers, so they must equal the
  # browser's: test/models/cyvasse_rules/js_agreement_test.rb replays the JS
  # engine's own answers (test/fixtures/files/rules_agreement.json) against
  # this port, and test/lib/engine_rulebook_agreement_test.rb pins the table.
  module Units
    Type = Data.define(:codename, :name, :rank, :attack, :defence, :move_range, :attack_range, :trump) do
      def mountain? = codename == "mountain"
      def dragon? = codename == "dragon"
      def king? = codename == "king"
      def cavalry? = rank == "cavalry"
      def range? = rank == "range"
    end

    def self.type(codename, name, rank, attack:, defence:, move:, range:, trump: [])
      Type.new(codename:, name:, rank:, attack:, defence:, move_range: move, attack_range: range, trump: trump.freeze)
    end
    private_class_method :type

    TYPES = [
      type("rabble", "Rabble", "vanguard", attack: 1, defence: 1, move: 3, range: 0),
      type("spearman", "Spearman", "vanguard", attack: 2, defence: 2, move: 2, range: 0, trump: [ "lighthorse" ]),
      type("elephant", "Elephant", "vanguard", attack: 4, defence: 4, move: 3, range: 0),
      type("lighthorse", "Light Horse", "cavalry", attack: 2, defence: 2, move: 3, range: 0),
      type("heavyhorse", "Heavy Horse", "cavalry", attack: 3, defence: 3, move: 2, range: 0),
      type("crossbowman", "Crossbowman", "range", attack: 2, defence: 1, move: 1, range: 2, trump: [ "elephant" ]),
      type("trebuchet", "Trebuchet", "range", attack: 1, defence: 1, move: 0, range: 3, trump: [ "dragon" ]),
      type("catapult", "Catapult", "range", attack: 3, defence: 1, move: 2, range: 3, trump: [ "dragon" ]),
      type("dragon", "Dragon", "unique", attack: 5, defence: 5, move: 10, range: 0),
      type("king", "King", "unique", attack: 2, defence: 2, move: 2, range: 0),
      type("mountain", "Mountain", "mountain", attack: 9, defence: 9, move: 0, range: 0)
    ].index_by(&:codename).freeze

    # The army by the legacy 1-based data-index. Every stored setup string
    # ("11:39|6:38|...") names units by this index, so the order is load-bearing.
    ARMY = %w[
      rabble rabble rabble
      spearman spearman
      elephant elephant
      lighthorse lighthorse
      heavyhorse heavyhorse
      crossbowman crossbowman
      trebuchet
      catapult
      dragon
      king
      mountain mountain
    ].freeze

    ARMY_SIZE = ARMY.size
    KING_INDEX = ARMY.index("king") + 1

    def self.type_at(index)
      codename = index.is_a?(Integer) && index.between?(1, ARMY_SIZE) ? ARMY[index - 1] : nil
      raise ArgumentError, "no unit at army index #{index.inspect}" unless codename

      TYPES.fetch(codename)
    end
  end
end
