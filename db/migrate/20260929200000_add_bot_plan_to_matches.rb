# A live computer turn played in visible steps (task cyvasse-bot-move-pacing):
# the turn chosen up front and how far it has been shown (LiveMatch#bot_plan).
class AddBotPlanToMatches < ActiveRecord::Migration[8.1]
  def change
    add_column :matches, :bot_plan, :jsonb
  end
end
