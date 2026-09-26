module CyvasseRules
  # What a selected unit may do: where it can move and what it can capture.
  # A line-for-line mirror of app/javascript/cyvasse/rules.js, kept literal on
  # purpose (the same shared ring map, the same iteration order) so that the
  # server refuses exactly the moves the browser never offers. The ring
  # encoding is documented in rules.js:
  #
  #   ring = code * 10 + step      step = distance - 1 (0-based)
  #
  # test/models/cyvasse_rules/js_agreement_test.rb holds this file to the JS
  # engine's own output.
  module Rules
    SELECTED = 9
    UNRINGED = 8
    PREVIEW_CODE = { 1 => 6, 4 => 7, 5 => 8 }.freeze

    Actions = Data.define(:moves, :attacks)

    # position: anything with piece_at(hex_index) -> piece (#team, #type) or nil.
    # jump: 1, or 2 for a cavalry unit's second jump.
    def self.legal_actions(position, origin_index, jump: 1)
      origin = Board.hex_at(origin_index)
      piece = origin && position.piece_at(origin_index)
      raise ArgumentError, "no unit on hex #{origin_index}" unless piece

      type = piece.type
      rings = { origin_index => SELECTED }

      potential_move = PotentialRange.call(origin, type.move_range, dragon: type.dragon?).to_a.sort

      if type.cavalry? && jump == 1
        preview = PotentialRange.call(origin, type.move_range + 2).to_a.sort
        walk_move_rings(position, piece, rings, preview, type.move_range + 2, preview: true)
      end
      steps = type.cavalry? && jump == 2 ? 2 : type.move_range
      walk_move_rings(position, piece, rings, potential_move, steps)

      ring_of = ->(index) { rings.fetch(index, UNRINGED) }
      moves = potential_move.select { |i| ring_of.(i).between?(10, 19) }

      attacks = if type.range?
        range_rings = { origin_index => SELECTED }
        potential_shot = PotentialRange.call(origin, type.attack_range).to_a.sort
        walk_range_rings(position, piece, origin, range_rings, potential_shot)
        potential_shot.select { |i| range_rings.fetch(i, UNRINGED).between?(20, 29) }
      else
        potential_move.select { |i| ring_of.(i).between?(30, 49) }
      end

      Actions.new(moves:, attacks:)
    end

    def self.walk_move_rings(position, piece, rings, candidates, steps, preview: false)
      locked = Set.new
      type = piece.type

      steps.times do |step|
        passable = [ step + 9, step + 19, step + 29, step + 59 ]
        candidates.reject { |i| locked.include?(i) }.each do |index|
          next unless Board.neighbors(Board.hex_at(index)).any? { |n| passable.include?(rings[n.index]) }

          occupant = position.piece_at(index)
          code = type.dragon? ? dragon_code(piece, occupant) : standard_code(piece, occupant)
          rings[index] = step + (preview ? PREVIEW_CODE.fetch(code) : code) * 10
          locked << index
        end
      end
    end

    def self.standard_code(piece, occupant)
      return 1 unless occupant
      return 5 if occupant.type.mountain? || occupant.team == piece.team

      type = piece.type
      code = occupant.type.defence > type.attack ? 5 : 4
      code = 4 if type.trump.include?(occupant.type.codename)
      code = 5 if occupant.type.trump.include?(type.codename)
      code
    end

    def self.dragon_code(piece, occupant)
      return 1 unless occupant
      return 2 if occupant.type.mountain? || occupant.team == piece.team
      if occupant.type.range? || occupant.type.dragon?
        return %w[trebuchet catapult].include?(occupant.type.codename) ? 5 : 4
      end

      3
    end

    def self.walk_range_rings(position, piece, origin, rings, candidates)
      locked = Set.new
      type = piece.type
      rings_around = ->(index) { Board.neighbors(Board.hex_at(index)).map { |n| rings[n.index] } }

      type.attack_range.times do |step|
        candidates.reject { |i| locked.include?(i) }.each do |index|
          around = rings_around.(index)

          if around.include?(step + 9) || around.include?(step + 19)
            occupant = position.piece_at(index)
            ring = step + 10
            if occupant&.type&.mountain?
              ring = step + (Board.in_a_row?(origin, Board.hex_at(index)) ? 40 : 30)
            elsif occupant && occupant.team != piece.team
              ring = step + (occupant.type.defence > type.attack ? 10 : 20)
              ring = step + 20 if type.trump.include?(occupant.type.codename)
              ring = step + 10 if occupant.type.trump.include?(type.codename)
            end
            ring = step + 30 if around.include?(step + 29)
            rings[index] = ring
            locked << index
          elsif around.include?(step + 39) || around.include?(step + 49)
            rings[index] = step + 30
            locked << index
          end
        end
      end
    end

    private_class_method :walk_move_rings, :standard_code, :dragon_code, :walk_range_rings
  end
end
