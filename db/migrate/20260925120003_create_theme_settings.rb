class CreateThemeSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :theme_settings do |t|
      t.string :app_name
      t.string :primary
      t.string :dark
      t.string :light
      t.string :accent1
      t.string :accent2
      t.string :warning
      t.string :danger

      t.timestamps
    end

    add_index :theme_settings, :app_name, unique: true
  end
end
