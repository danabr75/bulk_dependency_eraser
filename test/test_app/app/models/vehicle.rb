class Vehicle < ApplicationRecord
  has_many :parts, as: :partable, dependent: :destroy

  has_many :users_vehicles, dependent: :destroy
  has_many :users, through: :users_vehicles

  belongs_to :brand, optional: true
  belongs_to :owner, class_name: 'User', optional: true

  belongs_to :rented_by, class_name: 'User', optional: true

  def make_and_model
    "#{make} #{model}"
  end
end
