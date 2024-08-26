class User < ApplicationRecord
  has_many :users_vehicles
  has_many :vehicles, through: :users_vehicles

  has_many :owned_vehicles, foreign_key: :owner_id, class_name: 'Vehicle'
  has_many :owned_brands, through: :owned_vehicles, source: :brand

  # makes no logical sense to delete family members, but using as a test use-case
  # - NOTE: associates to itself
  has_many :probable_family_members, class_name: 'User', foreign_key: :last_name, primary_key: :last_name, dependent: :destroy

  # makes no logical sense to nullify other peoples first names, but using as a test use-case.
  # - NOTE: associates to itself
  has_many :similarly_named_users, -> { active }, class_name: 'User', foreign_key: :first_name, primary_key: :first_name, dependent: :nullify

  # TODO: create friendly_with table, joins users to other users, join table with ID use-case

  scope :active, -> { where(active: true) }

  def full_name
    "#{first_name} #{last_name}"
  end
end
