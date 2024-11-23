class User < ApplicationRecord
  # has_many through join WITH id
  has_many :users_vehicles, dependent: :destroy
  has_many :vehicles, through: :users_vehicles

  has_many :owned_vehicles, foreign_key: :owner_id, class_name: 'Vehicle', dependent: :destroy
  has_many :owned_brands, through: :owned_vehicles, source: :brand

  has_many :owned_motorcycles, foreign_key: :owner_id, class_name: 'Motorcycle', dependent: :destroy
  has_many :owned_cars,        foreign_key: :owner_id, class_name: 'Car', dependent: :destroy

  has_many :rented_vehicles, class_name: 'Vehicle', foreign_key: :rented_by_id, dependent: :nullify

  has_many :rented_vehicles_10, -> { limit(10).order(created_at: :desc) }, class_name: 'Vehicle', foreign_key: :rented_by_id, dependent: :nullify

  # makes no logical sense, but using as a test use-case
  has_many :people_who_have_my_last_name_as_a_first_name, class_name: 'User', foreign_key: :first_name, primary_key: :last_name, dependent: :nullify

  # makes no logical sense to nullify other peoples first names, but using as a test use-case.
  # - tests with scope
  has_many :people_who_have_my_first_name_as_a_last_name, -> {
    active.where.not(first_name: ['', nil])
  }, class_name: 'User', foreign_key: :last_name, primary_key: :first_name, dependent: :nullify

  has_many :user_is_friends_withs, dependent: :destroy
  has_many :friends, through: :user_is_friends_withs, source: :friends_with

  has_many :user_is_friended_by, foreign_key: :friends_with_id, class_name: 'UserIsFriendsWith', dependent: :destroy
  has_many :is_considered_friend_by, through: :user_is_friended_by, source: :user

  scope :active, -> { where(active: true) }

  has_one :profile, inverse_of: :user, dependent: :destroy

  has_one :nullification_profile, inverse_of: :user, dependent: :nullify

  has_one :poly_profile, inverse_of: :profilable, as: :profilable, dependent: :destroy

  has_one :nullify_poly_profile, inverse_of: :profilable, as: :profilable, dependent: :nullify

  # has_many polymorphic use-case
  has_many :registrations, inverse_of: :registerable, as: :registerable, dependent: :destroy
  has_many :nullify_registrations, inverse_of: :registerable, as: :registerable, dependent: :nullify

  # Restrict cases
  has_many :messages, dependent: :restrict_with_error
  has_many :texts,    dependent: :restrict_with_exception

  def full_name
    "#{first_name} #{last_name}"
  end
end
