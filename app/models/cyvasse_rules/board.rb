module CyvasseRules
  # The 91-hex board, in the legacy coordinates: a Ruby mirror of
  # app/javascript/cyvasse/board.js. Eleven rows, 6 hexes wide at the edges
  # and 11 across the middle; index 1..91 row by row from the top.
  #
  # Seats: the home player deploys on rows 7-11 (hexes 52-91), the away player
  # on rows 1-5 (hexes 1-40). The legacy app stored both armies from the home
  # seat and showed the away player the board turned round, hex 92 - index.
  module Board
    Hex = Data.define(:index, :x, :y, :size)

    ROWS = 11
    HEX_COUNT = 91
    HOME_ZONE = (52..91)
    AWAY_ZONE = (1..40)

    def self.row_size(y)
      y < 7 ? y + 5 : 17 - y
    end

    HEXES = begin
      index = 0
      (1..ROWS).flat_map do |y|
        (1..row_size(y)).map { |x| Hex.new(index: index += 1, x:, y:, size: row_size(y)) }
      end.freeze
    end

    BY_COORD = HEXES.index_by { |hex| [ hex.x, hex.y ] }.freeze

    def self.hex_at(index)
      index.is_a?(Integer) && index.between?(1, HEX_COUNT) ? HEXES[index - 1] : nil
    end

    def self.hex_at_xy(x, y)
      BY_COORD[[ x, y ]]
    end

    # The legacy neighbour table (goodCode/neighbors.js): the top half, the
    # middle row and the bottom half each lean a different way.
    TOP = [ [ -1, -1 ], [ 0, -1 ], [ 1, 0 ], [ -1, 0 ], [ 1, 1 ], [ 0, 1 ] ].freeze
    MIDDLE = [ [ -1, -1 ], [ 1, 0 ], [ -1, 0 ], [ -1, 1 ], [ 0, -1 ], [ 0, 1 ] ].freeze
    BOTTOM = [ [ 0, -1 ], [ 1, -1 ], [ 1, 0 ], [ -1, 0 ], [ -1, 1 ], [ 0, 1 ] ].freeze

    NEIGHBORS = HEXES.to_h do |hex|
      offsets = if hex.index < 41 then TOP elsif hex.index < 52 then MIDDLE else BOTTOM end
      [ hex.index, offsets.filter_map { |dx, dy| hex_at_xy(hex.x + dx, hex.y + dy) }.freeze ]
    end.freeze

    def self.neighbors(hex)
      NEIGHBORS.fetch(hex.index)
    end

    # The same hex seen from the other side of the table.
    def self.mirror(index)
      HEX_COUNT + 1 - index
    end

    # Whether two hexes share a row or a diagonal (hexRange/check.js, the
    # `inARow` of rules.js). Mountains in a shooter's line throw a longer shadow.
    def self.in_a_row?(hex1, hex2)
      return true if hex1.y == hex2.y

      size_of_row = ->(y) { y.between?(1, 11) ? row_size(y) : nil }
      lt = ->(a, b) { !a.nil? && !b.nil? && a < b }
      distance = (hex1.y - hex2.y).abs
      constant_up = 0
      constant_down = 0
      distance.times do |i|
        constant_down += 1 if lt.(size_of_row.(hex1.y + i), size_of_row.(hex1.y + i + 1))
        constant_up += 1 if lt.(size_of_row.(hex1.y - i - 1), size_of_row.(hex1.y - i))
      end

      [
        [ hex1.x - constant_up, hex1.y - distance ],
        [ hex1.x + distance - constant_up, hex1.y - distance ],
        [ hex1.x + constant_down, hex1.y + distance ],
        [ hex1.x - distance + constant_down, hex1.y + distance ]
      ].any? { |x, y| x == hex2.x && y == hex2.y }
    end
  end
end
