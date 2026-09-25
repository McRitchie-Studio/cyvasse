class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email
      # provider/uid stay nil until Google sign-in is enabled — kept from birth
      # so turning it on later is a config change, not a migration.
      t.string :provider
      t.string :uid
      t.string :role, default: "viewer"
      t.string :slug

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :slug, unique: true
    add_index :users, [ :provider, :uid ], unique: true
  end
end
