class CreateErrorLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :error_logs do |t|
      t.string :slug
      t.text :message
      t.text :inspect
      t.text :backtrace
      t.string :target_type
      t.bigint :target_id
      t.string :target_name
      t.string :parent_type
      t.bigint :parent_id
      t.string :parent_name

      t.timestamps
    end

    add_index :error_logs, :slug, unique: true
  end
end
