class Vehicle < ApplicationRecord
  has_many :parts, as: :partable, dependent: :destroy

  has_many :users_vehicles, dependent: :destroy
  has_many :users, through: :users_vehicles

  def make_and_model
    "#{make} #{model}"
  end
end
