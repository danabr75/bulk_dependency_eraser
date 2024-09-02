class VehicleAlsoWithNoDependents < Vehicle
  # Override dependency
  has_many :parts, as: :partable

  has_many :users_vehicles
  has_many :users, through: :users_vehicles

  belongs_to :brand
  belongs_to :owner, class_name: 'User', optional: true
end
