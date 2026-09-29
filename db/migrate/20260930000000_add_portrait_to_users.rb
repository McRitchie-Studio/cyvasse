# A computer player's portrait (task cyvasse-bot-portraits): the logical asset
# path of its picture under app/assets/images/bots, from the old Cyvasse app.
# Seeds set it (User.seed_computer_players!, the users:seed_computer_players
# post-deploy task), so every environment shows the same portraits. Blank for
# people and for any computer player without one (piece art instead).
class AddPortraitToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :portrait, :string
  end
end
