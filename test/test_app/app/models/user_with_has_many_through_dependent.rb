class UserWithHasManyThroughDependent < User
  has_many :owned_vehicles, foreign_key: :owner_id, class_name: 'Vehicle'
  has_many :owned_brands, through: :owned_vehicles, source: :brand, dependent: :destroy

  # Disable other associations
  has_many :users_vehicles, -> { none }
  has_many :probable_family_members, -> { none }, class_name: 'User', foreign_key: :last_name, primary_key: :last_name, dependent: :destroy
  has_many :similarly_named_users, -> { none }, class_name: 'User', foreign_key: :first_name, primary_key: :first_name, dependent: :nullify
end