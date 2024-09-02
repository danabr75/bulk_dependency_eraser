class User < ApplicationRecord
  # has_many through join WITH id
  has_many :users_vehicles, dependent: :destroy
  has_many :vehicles, through: :users_vehicles

  has_many :owned_vehicles, foreign_key: :owner_id, class_name: 'Vehicle', dependent: :destroy
  has_many :owned_brands, through: :owned_vehicles, source: :brand

  has_many :owned_motorcycles, foreign_key: :owner_id, class_name: 'Motorcycle', dependent: :destroy
  has_many :owned_cars,        foreign_key: :owner_id, class_name: 'Car', dependent: :destroy

  # makes no logical sense, but using as a test use-case
  has_many :people_who_have_my_last_name_as_a_first_name, class_name: 'User', foreign_key: :last_name, primary_key: :first_name, dependent: :destroy

  # makes no logical sense to nullify other peoples first names, but using as a test use-case.
  # - tests with scope
  has_many :people_who_have_my_first_name_as_a_last_name, -> {
    active.where.not(first_name: ['', nil])
  }, class_name: 'User', foreign_key: :last_name, primary_key: :first_name, dependent: :nullify

  # # TODO: create friendly_with table, joins users to other users, join table with ID use-case
  # - no need, with locations
  # has_many :friends, dependent: :destroy
  # has_many :users, through: :friends

  scope :active, -> { where(active: true) }

  has_one :profile, inverse_of: :user, dependent: :destroy

  # Restrict Cases
  has_many :messages, dependent: :restrict_with_error
  has_many :texts,    dependent: :restrict_with_exception

  def full_name
    "#{first_name} #{last_name}"
  end
end
