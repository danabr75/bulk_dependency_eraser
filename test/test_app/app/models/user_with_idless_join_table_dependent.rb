class UserWithIdlessJoinTableDependent < User
  has_many :users_vehicles, dependent: :destroy
  has_many :vehicles, through: :users_vehicles
end
