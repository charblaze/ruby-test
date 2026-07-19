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

ActiveRecord::Schema[8.1].define(version: 2026_07_13_000002) do
  create_table "subscription_events", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 4
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "event_type", null: false
    t.datetime "expires_date"
    t.string "notification_uuid"
    t.json "payload"
    t.datetime "purchase_date"
    t.string "source", null: false
    t.integer "subscription_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_subscription_events_on_created_at"
    t.index ["notification_uuid"], name: "index_subscription_events_on_notification_uuid", unique: true
    t.index ["subscription_id", "event_type"], name: "index_subscription_events_on_subscription_id_and_event_type"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "current_period_started_at"
    t.datetime "expires_at"
    t.string "product_id", null: false
    t.string "status", default: "provisional", null: false
    t.string "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_id"
    t.index ["expires_at"], name: "index_subscriptions_on_expires_at"
    t.index ["transaction_id"], name: "index_subscriptions_on_transaction_id", unique: true
    t.index ["user_id", "status"], name: "index_subscriptions_on_user_id_and_status"
  end

  add_foreign_key "subscription_events", "subscriptions"
end
