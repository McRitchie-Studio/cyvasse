# Play Now matchmaking (task play-now-matchmaking): a player searching for a
# live opponent, and the guest accounts that let anyone play without signing in.
class CreateLiveSeeks < ActiveRecord::Migration[8.1]
  def change
    create_table :live_seeks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :match, foreign_key: true
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :live_seeks, %i[match_id created_at]

    add_column :users, :guest, :boolean, null: false, default: false
  end
end
