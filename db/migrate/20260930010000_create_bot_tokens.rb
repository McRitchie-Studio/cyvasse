# A computer player's remote runner authenticates with a bearer token
# (task tyrion-bot-api). Only the SHA-256 digest is kept; see BotToken.
class CreateBotTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :bot_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :name
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :bot_tokens, :token_digest, unique: true
  end
end
