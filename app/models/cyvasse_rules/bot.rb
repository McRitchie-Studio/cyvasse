module CyvasseRules
  # The computer player on the server (live matches, task live-match-engine):
  # a port of the browser opponent in app/javascript/cyvasse/ai.js, so a
  # computer seat in an online match plays the way /play's computer does —
  # greedy and a little reckless. If any unit can capture, it takes the most
  # valuable piece on offer, the king above all; otherwise it picks a unit
  # with somewhere to go and makes a random legal move. A cavalry unit whose
  # first jump leaves it a second takes it the same way.
  #
  # It also sets up armies: a computer seat stands in one of the legacy
  # computer lineups (app/javascript/cyvasse/setups.js), and a player whose
  # setup clock runs out gets a random legal placement.
  module Bot
    # Least to most valuable; ties go to the last in board order, as the
    # legacy search's overwrite did (ai.js KILL_PRIORITY, the same list:
    # test/models/cyvasse_rules/units_parity_test.rb).
    KILL_PRIORITY = %w[rabble lighthorse crossbowman spearman heavyhorse elephant trebuchet catapult dragon king].freeze

    # The legacy computer lineups (setups.js COMPUTER_OPPONENTS), hexes 1-40 as
    # the computer stood at the top. mirror() turns each to the seat's own
    # rows (52-91), the frame Match#set_up! takes.
    LINEUPS = [
      "11:39|6:38|4:37|19:36|18:35|8:34|10:33|7:32|9:31|5:28|12:27|13:26|15:25|3:24|1:19|17:18|14:17|2:16|16:10|",
      "10:38|9:37|6:36|11:35|7:34|8:33|1:32|3:26|15:25|2:24|18:18|19:17|5:16|16:15|12:10|13:9|4:8|17:3|14:2|",
      "11:38|6:37|7:35|10:34|2:33|9:27|8:26|5:25|19:24|18:23|4:22|14:17|1:16|12:15|15:14|3:9|13:8|17:7|16:1|",
      "6:38|9:37|11:36|7:35|4:34|18:33|19:32|5:31|8:27|10:26|3:25|15:24|13:23|12:22|16:17|1:16|14:15|17:14|2:8|",
      "8:38|1:37|7:36|6:35|13:34|10:33|9:32|19:27|15:26|5:25|12:24|11:23|18:19|14:18|17:17|4:16|3:15|2:14|16:11|",
      "19:40|18:39|5:38|7:37|10:36|8:35|3:34|1:33|12:30|13:29|4:28|6:27|11:26|9:25|2:24|17:21|14:20|15:19|16:13|",
      "12:39|2:38|9:37|6:36|7:35|8:34|10:33|11:32|4:28|14:26|5:25|13:24|15:23|3:22|1:19|18:13|19:12|16:8|17:6|",
      "7:38|10:37|8:36|2:35|9:34|11:33|6:32|3:29|16:23|4:19|14:17|5:16|19:15|18:14|15:9|13:8|12:7|1:2|17:1|",
      "9:40|11:39|7:38|1:37|3:34|6:33|10:32|2:31|14:28|5:27|8:26|4:25|15:24|16:19|13:18|12:17|19:11|17:10|18:9|",
      "18:40|19:39|7:38|6:37|4:36|11:33|9:32|10:31|13:30|12:29|14:28|15:27|5:26|17:21|3:19|2:18|8:17|1:12|16:10|",
      "2:40|9:39|6:38|12:37|4:36|5:35|7:34|10:33|11:32|1:31|3:27|14:26|15:25|13:24|8:23|16:12|18:8|19:7|17:1|",
      "7:39|8:37|11:36|6:35|19:34|10:28|5:27|4:26|15:25|18:24|16:23|9:21|13:18|12:17|2:15|3:11|17:10|14:9|1:7|",
      "6:26|7:25|9:19|4:18|18:17|19:16|10:15|12:14|8:12|5:11|13:10|2:9|1:8|11:7|16:5|14:4|17:3|15:2|3:1|",
      "11:39|2:38|9:37|7:36|8:35|6:34|10:33|1:32|5:20|3:17|4:16|19:15|18:14|15:9|13:8|12:7|16:5|14:2|17:1|",
      "9:39|2:38|7:37|10:36|11:35|6:34|1:33|8:32|16:19|3:18|4:17|5:16|18:15|19:14|15:10|14:9|12:8|13:7|17:1|",
      "9:39|6:37|8:36|7:35|4:34|19:33|18:32|5:31|10:27|3:26|15:25|1:24|12:23|13:22|11:18|2:17|16:16|14:15|17:14|",
      "5:40|4:39|18:38|12:37|13:36|8:35|10:34|6:33|9:32|7:31|15:30|14:29|19:28|1:26|2:25|17:21|11:20|16:13|3:12|",
      "1:40|7:39|12:38|9:37|11:36|6:35|10:34|8:33|16:32|13:31|4:28|19:27|15:26|14:25|18:24|5:23|2:22|17:17|3:16|"
    ].freeze

    module_function

    # A computer lineup from the seat's own rows (hexes 52-91).
    def lineup(rng: Random.new)
      pairs = Game.parse_lineup!(LINEUPS.sample(random: rng).split("|").reject(&:empty?).map do |pair|
        index, hex = pair.split(":").map(&:to_i)
        "#{index}:#{Board.mirror(hex)}|"
      end.join)
      Game.format(pairs)
    end

    # The whole army on distinct random hexes of the seat's own rows.
    def random_lineup(rng: Random.new)
      hexes = Board::HOME_ZONE.to_a.shuffle(random: rng)
      Game.format((1..Units::ARMY_SIZE).map { |index| [ index, hexes.pop ] })
    end

    # The side to move's whole turn as Game#play! takes it — [[from, to]], or
    # two steps for a cavalry double jump — or nil when it has no move.
    def choose_turn(game, rng: Random.new)
      first = choose_step(game, movers(game), rng:)
      return nil unless first

      from, to = first
      unit = game.piece_at(from)
      target = game.piece_at(to)
      return [ first ] unless unit.type.cavalry? && !target&.type&.king?

      after = after_step(game, from, to)
      second = choose_step(after, [ to ], rng:, jump: 2)
      second ? [ first, second ] : [ first ]
    end

    # One step for one of `hexes` (the side to move's units): the best capture
    # on offer, else a random unit with somewhere to go and a random action
    # (an attack when it has one, as ai.js does).
    def choose_step(game, hexes, rng:, jump: 1)
      actions = hexes.to_h { |hex| [ hex, game.legal_actions(hex, jump:) ] }
      kill = best_kill(game, actions)
      return kill if kill

      able = actions.select { |_, a| a.moves.any? || a.attacks.any? }
      return nil if able.empty?

      from, a = able.to_a.sample(random: rng)
      [ from, (a.attacks.any? ? a.attacks : a.moves).sample(random: rng) ]
    end

    def best_kill(game, actions)
      best = nil
      best_rank = -1
      actions.each do |from, a|
        a.attacks.each do |to|
          rank = KILL_PRIORITY.index(game.piece_at(to).type.codename) || -1
          next unless rank >= best_rank

          best = [ from, to ]
          best_rank = rank
        end
      end
      best
    end

    # The side to move's units that can act, in board order; mountains never do.
    def movers(game)
      game.units.select { |u| u.alive? && u.team == game.offense && !u.type.mountain? }.map(&:hex).sort
    end

    # A copy of `game` with the first step of a turn applied, to find a
    # cavalry unit's second jump without touching the real game.
    def after_step(game, from, to)
      copy = Game.new(home: game.position(Game::HOME), away: game.position(Game::AWAY), offense: game.offense, turn: game.turn)
      unit = copy.piece_at(from)
      target = copy.piece_at(to)
      if target
        target.status = :dead
        target.hex = nil
      end
      unit.hex = to if target.nil? || unit.type.attack_range.zero?
      copy
    end
  end
end
