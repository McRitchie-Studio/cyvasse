module CyvasseRules
  # Every hex a unit could reach if nothing stood in the way: a line-for-line
  # mirror of app/javascript/cyvasse/potential_range.js (itself a port of the
  # legacy hexRange/potentialRange.js). For every unit but the dragon it is
  # the full hex disc of the radius; for the dragon, six straight lines.
  #
  # JavaScript compares `undefined < n` as false where Ruby raises, so every
  # size comparison goes through `lt`.
  module PotentialRange
    def self.call(origin, range, dragon: false)
      found = Set.new
      x_pos = origin.x
      y_pos = origin.y
      size_at = ->(x, y) { Board.hex_at_xy(x, y)&.size }
      mark = ->(x, y) { (hex = Board.hex_at_xy(x, y)) && found << hex.index }
      lt = ->(a, b) { !a.nil? && !b.nil? && a < b }

      (1..range).each do |horizontal|
        constant_up = 0
        constant_down = 0
        initial_size_down = size_at.(x_pos, y_pos)
        initial_size_up = size_at.(x_pos, y_pos)

        mark.(x_pos - horizontal, y_pos)
        mark.(x_pos + horizontal, y_pos)

        (1..horizontal).each do |vertical|
          final_size_down = size_at.(x_pos, y_pos + vertical)
          final_size_up = size_at.(x_pos, y_pos - vertical)

          constant_down += 1 if lt.(initial_size_down, final_size_down)
          constant_up += 1 if lt.(initial_size_up, final_size_up)

          [ [ constant_down, vertical ], [ constant_up, -vertical ] ].each do |constant, up|
            if dragon
              if horizontal <= vertical
                xx = x_pos - (horizontal - vertical - constant)
                mark.(xx, y_pos + up)
                mark.(xx - horizontal, y_pos + up)
              end
            elsif horizontal <= vertical
              (0..horizontal).each { |row| mark.(x_pos - (horizontal + row - vertical - constant), y_pos + up) }
            else
              mark.(x_pos - (horizontal - constant), y_pos + up)
              mark.(x_pos + (horizontal + constant - vertical), y_pos + up)
            end
          end

          initial_size_down = final_size_down
          initial_size_up = final_size_up
        end
      end
      found
    end
  end
end
