class Vehicle < ApplicationRecord
  has_many :parts, as: :partable, dependent: :destroy

  has_many :users_vehicles
  has_many :users, through: :users_vehicles

  belongs_to :brand
  belongs_to :owner, class_name: 'User', optional: true

  def make_and_model
    "#{make} #{model}"
  end
end
