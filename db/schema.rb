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

ActiveRecord::Schema[8.1].define(version: 2026_05_05_004213) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "restaurants", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "name", null: false
    t.integer "proximity_radius_meters", default: 200, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_restaurants_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "wine_bottles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "glasses_remaining", default: 0, null: false
    t.datetime "opened_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "wine_id", null: false
    t.index ["wine_id", "status"], name: "index_wine_bottles_on_wine_id_and_status"
    t.index ["wine_id"], name: "index_wine_bottles_on_wine_id"
  end

  create_table "wines", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "available_glasses", default: 0, null: false
    t.integer "bottle_size_ml", default: 750, null: false
    t.integer "color", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "grape_variety"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_100ml_cents"
    t.integer "price_125ml_cents"
    t.integer "price_150ml_cents"
    t.integer "price_75ml_cents"
    t.integer "price_bottle_cents"
    t.string "producer"
    t.string "region"
    t.bigint "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "vintage_year"
    t.index ["restaurant_id", "color"], name: "index_wines_on_restaurant_id_and_color"
    t.index ["restaurant_id", "position"], name: "index_wines_on_restaurant_id_and_position"
    t.index ["restaurant_id"], name: "index_wines_on_restaurant_id"
  end

  add_foreign_key "restaurants", "users"
  add_foreign_key "wine_bottles", "wines"
  add_foreign_key "wines", "restaurants"
end
