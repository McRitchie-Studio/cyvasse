# Shared by the live-match tests: a computer turn planned as a cavalry double
# jump (task cyvasse-bot-move-pacing). The opening leaves the bot little
# choice, so the steps are picked by the rules directly; apply_turn checks them.
module LiveBot
  def plan_double_jump(match)
    game = match.to_game
    steps = CyvasseRules::Bot.movers(game).filter_map do |hex|
      next unless game.piece_at(hex).type.cavalry?

      game.legal_actions(hex).moves.filter_map do |to|
        second = CyvasseRules::Bot.after_step(game, hex, to).legal_actions(to, jump: 2).moves.first
        [ [ hex, to ], [ to, second ] ] if second
      end.first
    end.first
    assert steps, "a cavalry unit has a double jump"
    match.send(:schedule_bot, Random.new(1))
    match.bot_plan = match.bot_plan.merge("steps" => steps)
    match.save!
    match
  end
end
