class User < ApplicationRecord
  has_many :users_vehicles
  has_many :vehicles, through: :users_vehicles

  # makes no logical sense to delete family members, but using as a test use-case
  # - NOTE: associates to itself
  has_many :probable_family_members, class_name: 'User', foreign_key: :last_name, primary_key: :last_name, dependent: :destroy

  # makes no logical sense to nullify other peoples first names, but using as a test use-case.
  # - NOTE: associates to itself
  has_many :similarly_named_users, -> { active }, class_name: 'User', foreign_key: :first_name, primary_key: :first_name, dependent: :nullify

  scope :active, -> { where(active: true) }

  def full_name
    "#{first_name} #{last_name}"
  end
end
