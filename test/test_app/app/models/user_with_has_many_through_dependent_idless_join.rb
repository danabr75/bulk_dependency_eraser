# CAN'T WORK, NO ID ON users_vehicles
# - will raise ID error
class UserWithHasManyThroughDependentIdlessJoin < User
  has_many :users_vehicles
  has_many :vehicles, through: :users_vehicles, dependent: :destroy
end
