ActiveRecord::Schema.define(version: 2020_05_08_150547) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "hstore"
  enable_extension "pg_stat_statements"
  enable_extension "plpgsql"

  create_table "users", id: :integer, force: :cascade do |t|
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.boolean "active"
  end

  create_table "messages", id: :integer, force: :cascade do |t|
    t.text "message"
    t.bigint "user_id"
  end

  add_foreign_key "messages", "users"

  create_table "texts", id: :integer, force: :cascade do |t|
    t.text "text"
    t.bigint "user_id"
  end

  add_foreign_key "texts", "users"

  create_table "locations", id: :integer, force: :cascade do |t|
    t.string "name"
  end

  # # JOIN TABLE WITHOUT ID COLUMN
  # # - used to detect error if dependent
  create_table "users_locations", id: false, force: :cascade do |t|
    t.bigint "location_id"
    t.bigint "user_id"
  end

  add_foreign_key "users_locations", "locations"
  add_foreign_key "users_locations", "users"

  create_table "brands", id: :integer, force: :cascade do |t|
    t.string "name"
  end

  create_table "vehicles", id: :integer, force: :cascade do |t|
    t.string "model"
    t.string "type"
    t.bigint "brand_id"
    t.bigint "owner_id"
  end

  add_foreign_key "vehicles", "brands"
  add_foreign_key "vehicles", "users", column: 'owner_id'

  create_table "users_vehicles", id: :integer, force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "vehicle_id"
    t.index ["user_id"], name: "index_users_vehicles_on_user_id"
    t.index ["vehicle_id"], name: "index_users_vehicles_on_vehicle_id"
    t.index ["user_id", "vehicle_id"], name: "index_users_vehicles_on_user_id_and_vehicle_id", unique: true
  end

  add_foreign_key "users_vehicles", "users"
  add_foreign_key "users_vehicles", "vehicles"

  create_table "parts", id: :integer, force: :cascade do |t|
    t.string "name"
    t.bigint "partable_id"
    t.string "partable_type"
    t.index ["partable_type", "partable_id"], name: "index_parts_on_partable_type_and_partable_id"
  end

  create_table "logos", id: :integer, force: :cascade do |t|
    t.string "brand_name"
    t.bigint "brand_id"
  end

  add_foreign_key "logos", "brands"  

  create_table "addresses", id: :serial, force: :cascade do |t|
    t.string "street"
    t.bigint "user_id"
  end

  add_foreign_key "addresses", "users"  

  create_table "profiles", id: :serial, force: :cascade do |t|
    t.bigint "user_id"
    t.text "bio"
    t.index ["user_id"], name: "index_profiles_on_user_id"
  end

  add_foreign_key "profiles", "users"  

  # add_index "users", ["first_name", "last_name"], name: "index_users_on_first_and_last_name", unique: true
end