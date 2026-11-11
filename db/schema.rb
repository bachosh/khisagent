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

ActiveRecord::Schema[8.1].define(version: 2026_11_11_180500) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title"
    t.datetime "last_activity_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "last_activity_at"], name: "index_conversations_on_user_id_and_last_activity_at"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.string "role", null: false
    t.text "content", default: "", null: false
    t.string "status", default: "done", null: false
    t.string "progress"
    t.json "tool_steps", default: [], null: false
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "operations", force: :cascade do |t|
    t.integer "statement_id", null: false
    t.integer "position", null: false
    t.date "booked_on"
    t.text "description", default: "", null: false
    t.string "counterparty"
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.string "currency"
    t.decimal "balance", precision: 15, scale: 2
    t.string "mcc"
    t.string "transaction_code"
    t.string "category", default: "other", null: false
    t.string "category_group", default: "unknown", null: false
    t.index ["statement_id", "booked_on"], name: "index_operations_on_statement_id_and_booked_on"
    t.index ["statement_id", "category"], name: "index_operations_on_statement_id_and_category"
    t.index ["statement_id", "category_group"], name: "index_operations_on_statement_id_and_category_group"
    t.index ["statement_id", "position"], name: "index_operations_on_statement_id_and_position"
    t.index ["statement_id"], name: "index_operations_on_statement_id"
  end

  create_table "risk_reports", force: :cascade do |t|
    t.integer "statement_id", null: false
    t.integer "risk_score", null: false
    t.string "risk_level", null: false
    t.string "recommendation", null: false
    t.text "summary", null: false
    t.json "findings", default: [], null: false
    t.json "strengths", default: [], null: false
    t.json "metrics", default: {}, null: false
    t.decimal "estimated_monthly_income", precision: 15, scale: 2
    t.decimal "estimated_monthly_debt_payments", precision: 15, scale: 2
    t.string "language"
    t.string "model"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["statement_id"], name: "index_risk_reports_on_statement_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "statements", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "conversation_id", null: false
    t.integer "message_id"
    t.string "filename", null: false
    t.string "file_kind", null: false
    t.string "status", default: "queued", null: false
    t.string "progress"
    t.text "error"
    t.string "extraction_method"
    t.json "column_mapping"
    t.string "bank_name"
    t.string "account_holder"
    t.string "account_number"
    t.string "currency"
    t.date "period_start"
    t.date "period_end"
    t.decimal "opening_balance", precision: 15, scale: 2
    t.decimal "closing_balance", precision: 15, scale: 2
    t.integer "operations_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_statements_on_conversation_id"
    t.index ["message_id"], name: "index_statements_on_message_id"
    t.index ["user_id"], name: "index_statements_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "", null: false
    t.string "company"
    t.string "locale", default: "ka", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "conversations", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "operations", "statements"
  add_foreign_key "risk_reports", "statements"
  add_foreign_key "sessions", "users"
  add_foreign_key "statements", "conversations"
  add_foreign_key "statements", "messages"
  add_foreign_key "statements", "users"
end
