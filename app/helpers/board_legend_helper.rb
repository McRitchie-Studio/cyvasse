module BoardLegendHelper
  # The board key beside the threat switches (games/_threat_toggle): one entry
  # per look a hex can take in play, in the board's own colours (game.css
  # .cyvasse-legend-swatch, copied from the board rules above it).
  #
  #   key    the swatch's data-swatch, styled in game.css
  #   label  what the look means, short
  #   marks  the hex classes (cyvasse_game_controller.js) and edge kinds
  #          (cyvasse/edges EDGE_PRIORITY) that draw it; the component test
  #          holds every mark to the board code and every edge kind to an entry
  BoardLegendEntry = Data.define(:key, :label, :marks)

  BOARD_LEGEND = [
    BoardLegendEntry.new("selected", "Selected unit, last move", %w[is-selected is-last-move selected last-move]),
    BoardLegendEntry.new("yours", "Your unit", %w[team-1]),
    BoardLegendEntry.new("enemy", "Enemy unit", %w[team-0]),
    BoardLegendEntry.new("move", "Move here", %w[is-move is-lit ring]),
    BoardLegendEntry.new("attack", "Attack", %w[is-attack is-target target]),
    BoardLegendEntry.new("sunken", "Can pass, can't stop", %w[is-sunken]),
    BoardLegendEntry.new("ghost", "Cavalry's second jump", %w[is-ghost ghost-6 ghost-7 ghost-8]),
    BoardLegendEntry.new("field", "In range to shoot", %w[is-field field]),
    BoardLegendEntry.new("blocked", "Shot blocked", %w[is-blocked blocked]),
    BoardLegendEntry.new("reach", "Enemy can reach", %w[is-threatened perimeter perimeter-ranged]),
    BoardLegendEntry.new("danger", "Your unit in danger", %w[is-danger danger]),
    BoardLegendEntry.new("focus", "Hover, keyboard focus", %w[hex-cursor])
  ].freeze

  def board_legend
    BOARD_LEGEND
  end
end
