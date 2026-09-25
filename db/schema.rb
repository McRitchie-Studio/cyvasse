# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_25_222326) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "error_logs", force: :cascade do |t|
    t.text "backtrace"
    t.datetime "created_at", null: false
    t.text "inspect"
    t.text "message"
    t.bigint "parent_id"
    t.string "parent_name"
    t.string "parent_type"
    t.string "slug"
    t.bigint "target_id"
    t.string "target_name"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_error_logs_on_slug", unique: true
  end

# Could not dump table "studio_email_deliveries" because of following ArgumentError
#   wrong number of arguments (given 2, expected 1)


  create_table "studio_email_settings", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "cta_color"
    t.boolean "cta_enabled"
    t.string "cta_text"
    t.string "discord_url"
    t.string "email_key", null: false
    t.string "header"
    t.string "header_fallback"
    t.boolean "hide_logo", default: false, null: false
    t.string "logo_url"
    t.integer "scrim_percent"
    t.string "subject"
    t.string "subtext"
    t.datetime "updated_at", null: false
    t.index ["email_key"], name: "index_studio_email_settings_on_email_key", unique: true
  end

# Could not dump table "studio_enumerals" because of following ArgumentError
#   wrong number of arguments (given 2, expected 1)


# Could not dump table "studio_geo_settings" because of following ArgumentError
#   wrong number of arguments (given 2, expected 1)


# Could not dump table "studio_knowledge_docs" because of following ArgumentError
#   wrong number of arguments (given 2, expected 1)


  create_table "studio_knowledge_expectations", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "cadence", default: "once", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.string "entity", null: false
    t.string "path", default: "", null: false
    t.string "source_note"
    t.date "start_on"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["entity", "active"], name: "index_studio_knowledge_expectations_on_entity_and_active"
  end

# Could not dump table "studio_links" because of following ArgumentError
#   wrong number of arguments (given 2, expected 1)


  create_table "theme_settings", force: :cascade do |t|
    t.string "accent1"
    t.string "accent2"
    t.string "app_name"
    t.datetime "created_at", null: false
    t.string "danger"
    t.string "dark"
    t.string "light"
    t.string "primary"
    t.datetime "updated_at", null: false
    t.string "warning"
    t.index ["app_name"], name: "index_theme_settings_on_app_name", unique: true
  end

# Could not dump table "users" because of following ArgumentError
#   wrong number of arguments (given 2, expected 1)


  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "studio_email_deliveries", "users"
end
