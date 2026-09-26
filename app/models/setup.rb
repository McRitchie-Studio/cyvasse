# A saved army lineup (epic cyvasse-revival piece 10b), stored in the legacy
# setups columns (see the CreateSetups migration). A player keeps up to three,
# one per slot (button_position 1-3), and loads one into the setup phase of a
# game against the computer or an online match; the board then treats it like
# any army placed by hand.
#
#   Setup.slots_for(user)   { 1 => Setup or nil, 2 => ..., 3 => ... }
#   Setup.save_slot!(user, slot:, name:, lineup:)   replace one slot
#   setup.lineup            the army from the owner's seat, or nil
class Setup < ApplicationRecord
  SLOTS = (1..3)
  NAME_LENGTH = 20

  belongs_to :user

  # Checked on new lineups only: the importer writes legacy rows as they were.
  validates :name, presence: true, length: { maximum: NAME_LENGTH }, on: :create
  validates :button_position, inclusion: { in: SLOTS }, on: :create
  validate :a_whole_army, on: :create

  # Each slot's lineup: the newest in it that is a whole army. The legacy save
  # meant to replace a slot's lineup but sometimes left the old row behind; the
  # newest is the one the player saved last, unless it is not a whole army,
  # when the one before it still loads. A slot with no whole army shows its
  # newest row, which the page offers as nothing to load.
  def self.slots_for(user)
    rows = user ? where(user: user, button_position: SLOTS).order(created_at: :desc, id: :desc).group_by(&:button_position) : {}
    SLOTS.to_h { |slot| [ slot, rows[slot] && (rows[slot].find(&:lineup) || rows[slot].first) ] }
  end

  # Save `lineup` (from the player's seat) as `name` in `slot`, replacing
  # whatever the slot held.
  def self.save_slot!(user, slot:, name:, lineup:)
    transaction do
      where(user: user, button_position: slot.to_i).delete_all
      create!(user: user, button_position: slot.to_i, name: name.to_s.strip, units_position: lineup.to_s)
    end
  end

  # The army as the board places it: from the owner's seat, hexes 52-91,
  # sorted by unit. A handful of legacy lineups were saved from the away seat
  # unturned (hexes 1-40); they are turned round. Nil when the string is not a
  # whole army on one side's five rows, so the page never offers it.
  def lineup
    pairs = CyvasseRules::Game.parse_lineup!(units_position)
    CyvasseRules::Game.format(pairs)
  rescue CyvasseRules::Game::IllegalMove
    turned = turned_round
    turned && CyvasseRules::Game.format(turned)
  end

  # What the page needs to draw one slot.
  def as_slot
    { name: name.to_s, lineup: lineup }
  end

  private

  def turned_round
    turned = units_position.to_s.split("|").reject(&:empty?).map do |pair|
      unit, hex = pair.split(":", 2)
      "#{unit}:#{hex.to_s.match?(/\A\d+\z/) ? CyvasseRules::Board.mirror(hex.to_i) : hex}|"
    end
    CyvasseRules::Game.parse_lineup!(turned.join)
  rescue CyvasseRules::Game::IllegalMove
    nil
  end

  def a_whole_army
    CyvasseRules::Game.parse_lineup!(units_position)
  rescue CyvasseRules::Game::IllegalMove => e
    errors.add(:units_position, "is not a whole army on your five rows (#{e.message})")
  end
end
