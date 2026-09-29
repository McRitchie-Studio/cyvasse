# The email sign-in handoff (EmailHandoff) and the onboarding for incomplete
# accounts (User::Onboarding), task cyvasse-legacy-onboarding-handoff.
class CreateEmailHandoffTables < ActiveRecord::Migration[8.1]
  def change
    # Every assertion id (jti) spent, until it expires: the unique index is the
    # replay lock, shared by every dyno.
    create_table :email_handoff_nonces do |t|
      t.string :jti, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :email_handoff_nonces, :jti, unique: true
    add_index :email_handoff_nonces, :expires_at

    # One row per request to the endpoint, for the admin table. No email and no
    # assertion: the outcome, why, and the account signed in.
    create_table :email_handoff_attempts do |t|
      t.string :outcome, null: false
      t.string :reason
      t.bigint :user_id
      t.datetime :created_at, null: false
    end
    add_index :email_handoff_attempts, :created_at
    add_index :email_handoff_attempts, %i[outcome reason]
    add_foreign_key :email_handoff_attempts, :users, on_delete: :nullify

    change_table :users, bulk: true do |t|
      # {"welcome" => {"status" => "shown" | "done" | "skipped", "at" => iso8601}}
      t.jsonb :onboarding_steps, null: false, default: {}
      # "Keep me posted about Cyvasse": nil until asked; the answer and when.
      t.boolean :email_updates
      t.datetime :email_updates_at
    end
  end
end
