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

ActiveRecord::Schema[8.1].define(version: 2026_09_26_000040) do
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

  create_table "matches", force: :cascade do |t|
    t.boolean "away_ready", default: false
    t.string "away_units_position"
    t.bigint "away_user_id", null: false
    t.datetime "created_at", null: false
    t.boolean "fast_game", default: false
    t.string "finish_reason"
    t.boolean "home_ready", default: false
    t.string "home_units_position"
    t.bigint "home_user_id", null: false
    t.string "last_move"
    t.integer "legacy_id"
    t.string "match_against", default: "human"
    t.string "match_status", default: "pending"
    t.datetime "time_of_last_move"
    t.integer "turn", default: 0
    t.datetime "updated_at", null: false
    t.string "utility_saved_hex"
    t.integer "who_started"
    t.integer "whos_turn"
    t.bigint "winner_id"
    t.index ["away_user_id"], name: "index_matches_on_away_user_id"
    t.index ["home_user_id"], name: "index_matches_on_home_user_id"
    t.index ["legacy_id"], name: "index_matches_on_legacy_id", unique: true
    t.index ["match_status", "time_of_last_move"], name: "index_matches_on_match_status_and_time_of_last_move"
    t.index ["winner_id"], name: "index_matches_on_winner_id"
  end

  create_table "messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "legacy_id"
    t.bigint "match_id"
    t.text "message"
    t.boolean "read", default: false, null: false
    t.bigint "receiver_id", null: false
    t.bigint "sender_id", null: false
    t.datetime "updated_at", null: false
    t.index "LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id), created_at", name: "index_messages_on_conversation"
    t.index ["legacy_id"], name: "index_messages_on_legacy_id", unique: true
    t.index ["match_id", "created_at"], name: "index_messages_on_match_id_and_created_at"
    t.index ["receiver_id", "read"], name: "index_messages_on_receiver_id_and_read"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "setups", force: :cascade do |t|
    t.integer "button_position", null: false
    t.datetime "created_at", null: false
    t.integer "legacy_id"
    t.string "name"
    t.string "units_position", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["legacy_id"], name: "index_setups_on_legacy_id", unique: true
    t.index ["user_id", "button_position"], name: "index_setups_on_user_id_and_button_position"
  end

  create_table "studio_email_deliveries", force: :cascade do |t|
    t.string "action", null: false
    t.jsonb "args", default: [], null: false
    t.datetime "created_at", null: false
    t.string "email_key", null: false
    t.text "error"
    t.jsonb "kwargs", default: {}, null: false
    t.string "mailer", null: false
    t.boolean "sent", default: false, null: false
    t.datetime "sent_at"
    t.string "to"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_studio_email_deliveries_on_created_at"
    t.index ["email_key"], name: "index_studio_email_deliveries_on_email_key"
    t.index ["sent"], name: "index_studio_email_deliveries_on_sent"
    t.index ["user_id"], name: "index_studio_email_deliveries_on_user_id"
  end

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

  create_table "studio_enumerals", force: :cascade do |t|
    t.string "category", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "label"
    t.jsonb "metadata", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.integer "rank"
    t.datetime "updated_at", null: false
    t.index ["category", "key"], name: "index_studio_enumerals_on_category_and_key", unique: true
    t.index ["category", "position"], name: "index_studio_enumerals_on_category_and_position"
    t.index ["category", "rank"], name: "index_studio_enumerals_on_category_and_rank"
  end

  create_table "studio_geo_settings", force: :cascade do |t|
    t.string "app_name", null: false
    t.jsonb "banned_countries", default: []
    t.jsonb "banned_subdivisions", default: []
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["app_name"], name: "index_studio_geo_settings_on_app_name", unique: true
    t.index ["slug"], name: "index_studio_geo_settings_on_slug", unique: true
  end

  create_table "studio_knowledge_docs", force: :cascade do |t|
    t.jsonb "access", default: {}, null: false
    t.bigint "byte_size"
    t.string "category"
    t.datetime "created_at", null: false
    t.date "document_date"
    t.string "entity", null: false
    t.bigint "expectation_id"
    t.string "mime_type"
    t.string "path", default: "", null: false
    t.string "s3_key"
    t.string "source_note"
    t.string "status", default: "inbox", null: false
    t.text "summary"
    t.bigint "superseded_by_id"
    t.jsonb "tags", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uploaded_by"
    t.index ["entity", "path"], name: "index_studio_knowledge_docs_on_entity_and_path"
    t.index ["entity", "status"], name: "index_studio_knowledge_docs_on_entity_and_status"
    t.index ["expectation_id"], name: "index_studio_knowledge_docs_on_expectation_id"
    t.index ["s3_key"], name: "index_studio_knowledge_docs_on_s3_key", unique: true
    t.index ["superseded_by_id"], name: "index_studio_knowledge_docs_on_superseded_by_id"
  end

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

  create_table "studio_links", force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "kind", null: false
    t.bigint "linkable_id"
    t.string "linkable_type"
    t.jsonb "metadata", default: {}, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_studio_links_on_kind"
    t.index ["linkable_type", "linkable_id", "kind"], name: "idx_studio_links_owner_kind"
    t.index ["token"], name: "index_studio_links_on_token", unique: true
  end

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

  create_table "users", force: :cascade do |t|
    t.integer "birth_day"
    t.integer "birth_month"
    t.integer "birth_year"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name"
    t.jsonb "ip_locations", default: [], null: false
    t.integer "legacy_id"
    t.integer "losses", default: 0, null: false
    t.string "name"
    t.string "piece_skin"
    t.string "provider"
    t.string "role", default: "viewer"
    t.string "slug"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.string "username"
    t.integer "wins", default: 0, null: false
    t.index "lower((username)::text)", name: "index_users_on_lower_username"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["legacy_id"], name: "index_users_on_legacy_id", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["slug"], name: "index_users_on_slug", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "matches", "users", column: "away_user_id"
  add_foreign_key "matches", "users", column: "home_user_id"
  add_foreign_key "matches", "users", column: "winner_id"
  add_foreign_key "messages", "matches", on_delete: :nullify
  add_foreign_key "messages", "users", column: "receiver_id"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "setups", "users", on_delete: :cascade
  add_foreign_key "studio_email_deliveries", "users"
end
