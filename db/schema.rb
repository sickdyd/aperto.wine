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

ActiveRecord::Schema[8.1].define(version: 2026_08_17_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

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

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "glass_size_ml", null: false
    t.bigint "order_id", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.bigint "wine_id", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["wine_id"], name: "index_order_items_on_wine_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.string "guest_name"
    t.string "public_token", null: false
    t.bigint "restaurant_id", null: false
    t.bigint "restaurant_table_id"
    t.integer "status", default: 0, null: false
    t.integer "total_amount_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "status"], name: "index_orders_on_customer_id_and_status"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["public_token"], name: "index_orders_on_public_token", unique: true
    t.index ["restaurant_id", "created_at", "id"], name: "index_orders_on_restaurant_id_and_recency", order: { created_at: :desc, id: :desc }
    t.index ["restaurant_id", "status"], name: "index_orders_on_restaurant_id_and_status"
    t.index ["restaurant_id"], name: "index_orders_on_restaurant_id"
    t.index ["restaurant_table_id"], name: "index_orders_on_restaurant_table_id"
  end

  create_table "restaurant_tables", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "area"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "restaurant_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index "restaurant_id, COALESCE(area, ''::character varying), lower((name)::text)", name: "index_restaurant_tables_on_restaurant_area_name", unique: true
    t.index ["restaurant_id", "area", "position"], name: "index_restaurant_tables_on_restaurant_id_and_area_and_position"
    t.index ["restaurant_id"], name: "index_restaurant_tables_on_restaurant_id"
    t.index ["token"], name: "index_restaurant_tables_on_token", unique: true
  end

  create_table "restaurants", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "name", null: false
    t.integer "proximity_radius_meters", default: 200, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["slug"], name: "index_restaurants_on_slug", unique: true
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

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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

  create_table "wine_list_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "wine_id", null: false
    t.bigint "wine_list_id", null: false
    t.index ["wine_id"], name: "index_wine_list_items_on_wine_id"
    t.index ["wine_list_id", "position"], name: "index_wine_list_items_on_wine_list_id_and_position"
    t.index ["wine_list_id", "wine_id"], name: "index_wine_list_items_on_wine_list_id_and_wine_id", unique: true
  end

  create_table "wine_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.bigint "restaurant_id", null: false
    t.string "season"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id", "position"], name: "index_wine_lists_on_restaurant_id_and_position"
    t.index ["restaurant_id", "slug"], name: "index_wine_lists_on_restaurant_id_and_slug", unique: true
    t.index ["restaurant_id"], name: "index_wine_lists_on_one_published_per_restaurant", unique: true, where: "published"
    t.index ["restaurant_id"], name: "index_wine_lists_on_restaurant_id"
  end

  create_table "wine_references", force: :cascade do |t|
    t.decimal "abv", precision: 5, scale: 2
    t.string "color"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.string "food_pairings", default: [], null: false, array: true
    t.string "grape_variety"
    t.string "name", null: false
    t.string "producer"
    t.string "region"
    t.datetime "updated_at", null: false
    t.integer "vintages", default: [], null: false, array: true
    t.index ["external_id"], name: "index_wine_references_on_external_id", unique: true
    t.index ["name"], name: "index_wine_references_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["producer"], name: "index_wine_references_on_producer_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "wines", force: :cascade do |t|
    t.decimal "abv", precision: 5, scale: 2
    t.integer "acidity", limit: 2
    t.boolean "active", default: true, null: false
    t.string "aromas", default: [], null: false, array: true
    t.integer "available_glasses", default: 0, null: false
    t.boolean "biodynamic", default: false, null: false
    t.integer "body", limit: 2
    t.integer "bottle_size_ml", default: 750, null: false
    t.integer "color", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "favorite", default: false, null: false
    t.boolean "featured", default: false, null: false
    t.string "food_pairings", default: [], null: false, array: true
    t.string "grape_variety"
    t.string "image_url"
    t.string "name", null: false
    t.boolean "natural_wine", default: false, null: false
    t.boolean "organic", default: false, null: false
    t.integer "position", default: 0, null: false
    t.integer "price_100ml_cents"
    t.integer "price_125ml_cents"
    t.integer "price_150ml_cents"
    t.integer "price_75ml_cents"
    t.integer "price_bottle_cents"
    t.string "producer"
    t.string "region"
    t.bigint "restaurant_id", null: false
    t.string "short_description"
    t.string "style"
    t.integer "sweetness", limit: 2
    t.integer "tannins", limit: 2
    t.datetime "updated_at", null: false
    t.boolean "vegan", default: false, null: false
    t.integer "vintage_year"
    t.index ["restaurant_id", "color"], name: "index_wines_on_restaurant_id_and_color"
    t.index ["restaurant_id", "position"], name: "index_wines_on_restaurant_id_and_position"
    t.index ["restaurant_id", "position"], name: "index_wines_on_restaurant_id_and_position_where_featured", where: "featured"
    t.index ["restaurant_id"], name: "index_wines_on_restaurant_id"
    t.check_constraint "abv IS NULL OR abv >= 0::numeric AND abv <= 100::numeric", name: "wines_abv_range"
    t.check_constraint "acidity IS NULL OR acidity >= 0 AND acidity <= 5", name: "wines_acidity_range"
    t.check_constraint "body IS NULL OR body >= 0 AND body <= 5", name: "wines_body_range"
    t.check_constraint "sweetness IS NULL OR sweetness >= 0 AND sweetness <= 5", name: "wines_sweetness_range"
    t.check_constraint "tannins IS NULL OR tannins >= 0 AND tannins <= 5", name: "wines_tannins_range"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "wines"
  add_foreign_key "orders", "restaurant_tables", on_delete: :nullify
  add_foreign_key "orders", "restaurants"
  add_foreign_key "orders", "users", column: "customer_id"
  add_foreign_key "restaurant_tables", "restaurants", on_delete: :cascade
  add_foreign_key "restaurants", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "wine_bottles", "wines"
  add_foreign_key "wine_list_items", "wine_lists", on_delete: :cascade
  add_foreign_key "wine_list_items", "wines", on_delete: :cascade
  add_foreign_key "wine_lists", "restaurants", on_delete: :cascade
  add_foreign_key "wines", "restaurants"
end
