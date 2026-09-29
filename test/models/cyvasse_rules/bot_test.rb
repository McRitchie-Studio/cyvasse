require "test_helper"

# [unit] The server's computer player (CyvasseRules::Bot), a port of the
# browser AI (app/javascript/cyvasse/ai.js): it always takes the most valuable
# capture on offer, otherwise plays a legal move, and its turns are ones the
# rules engine accepts, cavalry double jumps included.
class CyvasseRules::BotTest < ActiveSupport::TestCase
  Bot = CyvasseRules::Bot
  Game = CyvasseRules::Game

  def self_play(seed, turns: 300)
    rng = Random.new(seed)
    away = Game.format(Game.mirror_lineup(Game.parse_lineup!(Bot.random_lineup(rng:))))
    game = Game.new(home: Bot.lineup(rng:), away:)
    game.start!(coin: -> { rng.rand(2) })
    turns.times do
      break if game.phase == :over

      steps = Bot.choose_turn(game, rng:)
      break unless steps

      yield game, steps if block_given?
      game.play!(steps)
    end
    game
  end

  test "its lineups are the browser's computer lineups, verbatim" do
    js = Rails.root.join("app/javascript/cyvasse/setups.js").read
    # Whole 19-unit lineups only: the file's header comment quotes a fragment.
    assert_equal js.scan(/"((?:\d+:\d+\|){19})"/).flatten, Bot::LINEUPS
  end

  test "a lineup and a random lineup are whole armies on the seat's own rows" do
    rng = Random.new(1)
    [ Bot.lineup(rng:), Bot.random_lineup(rng:) ].each do |lineup|
      pairs = Game.parse_lineup!(lineup)
      assert_equal (1..19).to_a, pairs.map(&:first).sort
      assert(pairs.all? { |_, hex| (52..91).cover?(hex) })
    end
  end

  test "every turn it plays is legal, and every game ends" do
    40.times do |seed|
      game = self_play(seed)
      assert_equal :over, game.phase, "seed #{seed} never finished"
    end
  end

  test "when a capture is on offer it takes the most valuable piece" do
    checked = 0
    20.times do |seed|
      self_play(seed) do |game, steps|
        movers = Bot.movers(game)
        targets = movers.flat_map { |hex| game.legal_actions(hex).attacks }.map { |to| game.piece_at(to).type.codename }
        next if targets.empty?

        best = targets.max_by { |codename| Bot::KILL_PRIORITY.index(codename) }
        taken = game.piece_at(steps.first.last)&.type&.codename
        assert_equal Bot::KILL_PRIORITY.index(best), Bot::KILL_PRIORITY.index(taken), "seed #{seed} turn #{game.turn}"
        checked += 1
      end
    end
    assert_operator checked, :>=, 20, "the self-play offered too few captures to test the rule"
  end

  test "a cavalry unit that can jump again does" do
    doubles = 0
    30.times do |seed|
      self_play(seed) { |_, steps| doubles += 1 if steps.size == 2 }
    end
    assert_operator doubles, :>, 0, "no cavalry double jump happened in 30 games"
  end
end
