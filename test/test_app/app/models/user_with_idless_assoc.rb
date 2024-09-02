class UserWithIdlessAssoc < User
  # foreign_key necessary when class name doesn't match foreign_key name
  has_many :users_locations, foreign_key: :user_id
  has_many :locations, through: :users_locations, dependent: :destroy
end