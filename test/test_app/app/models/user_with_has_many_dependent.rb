class UserWithHasManyDependent < User
  has_many :owned_vehicles, foreign_key: :owner_id, class_name: 'Vehicle', dependent: :destroy

  # Disable other associations
  has_many :users_vehicles, -> { none }
  has_many :probable_family_members, -> { none }, class_name: 'User', foreign_key: :last_name, primary_key: :last_name, dependent: :destroy
  has_many :similarly_named_users, -> { none }, class_name: 'User', foreign_key: :first_name, primary_key: :first_name, dependent: :nullify
end