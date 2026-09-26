module CyvasseRules
  # One online game on the server: the authority that accepts or refuses a
  # turn. It mirrors the play half of app/javascript/cyvasse/game.js (who
  # moves first, act, the cavalry double jump, the pass, the win) and reads and
  # writes the legacy match columns unchanged.
  #
  # Frame: the legacy canonical one, from the home seat. Home is team 1 on
  # hexes 52-91, away is team 0 on hexes 1-40, and `offense` is the legacy
  # `whos_turn` (1 home, 0 away). The browser draws the away player's board
  # turned round; Match#state_for does that translation, never this class.
  #
  # Position strings are the legacy `home_units_position` format,
  # `unitIndex:location|` per unit, where location is a hex, `g<team>` for a
  # captured unit, or `lDock` for one still in the dock.
  class Game
    HOME = 1
    AWAY = 0

    class IllegalMove < StandardError; end

    Unit = Struct.new(:team, :index, :type, :status, :hex) do
      def alive? = status == :alive
    end

    Result = Data.define(:captured, :last_move, :util_move, :passed, :over, :winner)

    attr_reader :units, :offense, :turn, :winner, :phase, :first_mover

    # home/away: the two position strings; offense: whos_turn; turn: the count.
    def initialize(home:, away:, offense: nil, turn: 0)
      @units = self.class.parse(home, HOME) + self.class.parse(away, AWAY)
      @offense = offense
      @turn = turn.to_i
      @phase = offense.nil? ? :setup : :play
      @winner = nil
    end

    # A setup string as the player submits it, from their own seat: every army
    # index 1..19 once, each on a distinct hex of rows 7-11 (52-91). Returns
    # the pairs, or raises IllegalMove naming what is wrong.
    def self.parse_lineup!(string)
      pairs = string.to_s.split("|").reject(&:empty?).map do |pair|
        unit, hex = pair.split(":", 2)
        raise IllegalMove, "#{pair.inspect} is not unit:hex" unless unit.to_s.match?(/\A\d+\z/) && hex.to_s.match?(/\A\d+\z/)

        [ unit.to_i, hex.to_i ]
      end
      raise IllegalMove, "place all #{Units::ARMY_SIZE} units" unless pairs.map(&:first).sort == (1..Units::ARMY_SIZE).to_a
      raise IllegalMove, "units must stand on your five rows" unless pairs.all? { |_, hex| Board::HOME_ZONE.cover?(hex) }
      raise IllegalMove, "two units share a hex" unless pairs.map(&:last).uniq.size == pairs.size

      pairs
    end

    def self.format(pairs)
      pairs.sort_by(&:first).map { |unit, location| "#{unit}:#{location}|" }.join
    end

    # The away player's lineup, turned from their seat into the home frame.
    def self.mirror_lineup(pairs)
      pairs.map { |unit, hex| [ unit, Board.mirror(hex) ] }
    end

    def self.parse(string, team)
      string.to_s.split("|").reject(&:empty?).map do |pair|
        index, location = pair.split(":", 2)
        type = Units.type_at(index.to_i)
        if location.to_s.match?(/\A\d+\z/)
          Unit.new(team, index.to_i, type, :alive, location.to_i)
        elsif location.to_s.start_with?("g")
          Unit.new(team, index.to_i, type, :dead, nil)
        else
          Unit.new(team, index.to_i, type, :unplaced, nil)
        end
      end
    end

    def piece_at(hex)
      @units.find { |u| u.alive? && u.hex == hex }
    end

    def legal_actions(hex, jump: 1)
      Rules.legal_actions(self, hex, jump:)
    end

    def position(team)
      self.class.format(@units.select { |u| u.team == team }.map do |u|
        [ u.index, u.alive? ? u.hex : (u.status == :dead ? "g#{team}" : "lDock") ]
      end)
    end

    # Both armies are on the board: choose who moves first the legacy way
    # (Game.whoGoesFirst): the side whose king stands nearer the middle row
    # moves first; a tie is a coin toss. Returns a Result with passed/over set
    # if the first player happens to have no move at all.
    def start!(coin: -> { SecureRandom.random_number(2) })
      raise IllegalMove, "both armies must be placed" if @units.size != 2 * Units::ARMY_SIZE || @units.any? { |u| u.status == :unplaced }

      distance = ->(team) { (6 - Board.hex_at(king(team).hex).y).abs }
      away = distance.(AWAY)
      home = distance.(HOME)
      @offense = if away > home then HOME elsif away < home then AWAY else coin.call end
      @first_mover = @offense
      @turn = 1
      @phase = :play
      begin_turn
    end

    # Play one whole turn: one step, or two for a cavalry unit whose first
    # jump left it a second. Each step is [from, to] in the home frame.
    # Raises IllegalMove and leaves the game unchanged unless every step is
    # legal and the turn is complete.
    def play!(steps)
      raise IllegalMove, "the game is not in play" unless @phase == :play
      steps = Array(steps)
      raise IllegalMove, "a turn is one or two steps" unless steps.size.between?(1, 2)
      unless steps.all? { |s| s.is_a?(Array) && s.size == 2 && s.all?(Integer) }
        raise IllegalMove, "each step is [from, to]"
      end

      snapshot = @units.map(&:dup)
      begin
        play_steps(steps)
      rescue IllegalMove
        @units = snapshot
        raise
      end
    end

    private

    def play_steps(steps)
      captured = []
      (from, to) = steps[0]
      unit = selectable_unit!(from)
      target = act!(unit, from, to, jump: 1)
      captured << target if target
      util_move = nil
      last_move = [ from, to ]

      if unit.type.cavalry? && !target&.type&.king?
        # game.js marks the first jump's origin even when no second follows.
        util_move = from
        next_actions = legal_actions(unit.hex, jump: 2)
        if next_actions.moves.any? || next_actions.attacks.any?
          raise IllegalMove, "your cavalry must make its second jump" if steps.size < 2

          (from2, to2) = steps[1]
          raise IllegalMove, "the second jump starts where the first ended" unless from2 == unit.hex
          target2 = act!(unit, from2, to2, jump: 2)
          captured << target2 if target2
          last_move = [ from2, to2 ]
          steps = steps.drop(1)
        end
      end
      raise IllegalMove, "this turn has one step" if steps.size > 1

      finish_turn(captured:, last_move:, util_move:)
    end

    def selectable_unit!(hex)
      unit = piece_at(hex)
      raise IllegalMove, "no unit of yours on hex #{hex}" unless unit && unit.team == @offense

      unit
    end

    def act!(unit, from, to, jump:)
      actions = legal_actions(from, jump:)
      raise IllegalMove, "#{from} -> #{to} is not a legal action" unless actions.moves.include?(to) || actions.attacks.include?(to)

      target = piece_at(to)
      if target
        target.status = :dead
        target.hex = nil
        # Shooters stay put; everyone else steps into the captured hex.
        unit.hex = to if unit.type.attack_range.zero?
      else
        unit.hex = to
      end
      target
    end

    def finish_turn(captured:, last_move:, util_move:)
      unless king(1 - @offense).alive?
        @phase = :over
        @winner = @offense
        return Result.new(captured:, last_move:, util_move:, passed: false, over: true, winner: @winner)
      end
      @turn += 1
      @offense = 1 - @offense
      begin_turn(captured:, last_move:, util_move:)
    end

    # Nothing can move: the turn passes; if neither side can move, a draw
    # (the port's stalemate rule, game.js #beginTurn).
    def begin_turn(captured: [], last_move: nil, util_move: nil)
      result = ->(passed, over) { Result.new(captured:, last_move:, util_move:, passed:, over:, winner: @winner) }
      return result.(false, false) if any_action?(@offense)

      @offense = 1 - @offense
      @turn += 1
      return result.(true, false) if any_action?(@offense)

      @phase = :over
      @winner = nil
      result.(true, true)
    end

    def any_action?(team)
      @units.any? do |u|
        next false unless u.team == team && u.alive?

        actions = legal_actions(u.hex)
        actions.moves.any? || actions.attacks.any?
      end
    end

    def king(team)
      @units.find { |u| u.team == team && u.type.king? }
    end
  end
end
