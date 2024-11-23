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

  create_table "user_is_friends_withs", id: :integer, force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "friends_with_id"
    t.index ["user_id", "friends_with_id"], name: "index_user_friends_with"
    t.index ["friends_with_id", "user_id"], name: "index_friend_with_has_users"
  end

  create_table "registrations", id: :integer, force: :cascade do |t|
    t.boolean "active"
    t.bigint "registerable_id"
    t.string "registerable_type"
    t.index ["registerable_type", "registerable_id"], name: "index_registrations_on_registerable_type_and_registerable_id"
  end

  create_table "nullify_registrations", id: :integer, force: :cascade do |t|
    t.boolean "active"
    t.bigint "registerable_id"
    t.string "registerable_type"
    t.index ["registerable_type", "registerable_id"], name: "index_nulfy_registrations_on_reg_type_and_reg_id"
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
    t.bigint "rented_by_id"
  end

  add_foreign_key "vehicles", "brands"
  add_foreign_key "vehicles", "users", column: 'owner_id'
  add_foreign_key "vehicles", "users", column: 'rented_by_id'

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

  create_table "addresses", id: :integer, force: :cascade do |t|
    t.string "street"
    t.bigint "user_id"
  end

  add_foreign_key "addresses", "users"

  create_table "profiles", id: :integer, force: :cascade do |t|
    t.bigint "user_id"
    t.text "bio"
    t.index ["user_id"], name: "index_profiles_on_user_id"
  end

  add_foreign_key "profiles", "users"

  create_table "nullification_profiles", id: :integer, force: :cascade do |t|
    t.bigint "user_id"
    t.text "bio"
    t.index ["user_id"], name: "index_nullification_profiles_on_user_id"
  end

  add_foreign_key "nullification_profiles", "users"

  create_table "poly_profiles", id: :integer, force: :cascade do |t|
    t.text "bio"
    t.bigint "profilable_id"
    t.string "profilable_type"
    t.index ["profilable_type", "profilable_id"], name: "index_poly_profiles_on_profilable_type_and_profilable_id"
  end

  create_table "nullify_poly_profiles", id: :integer, force: :cascade do |t|
    t.text "bio"
    t.bigint "profilable_id"
    t.string "profilable_type"
    t.index ["profilable_type", "profilable_id"], name: "index_nullify_poly_profiles_on_profilable_type_and_profilable_id"
  end
end