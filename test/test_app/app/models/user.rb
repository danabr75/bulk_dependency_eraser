class User < ApplicationRecord
  has_many :users_vehicles, dependent: :destroy
  has_many :vehicles, through: :users_vehicles

  # makes no logical sense to delete family members, but using as a test use-case
  has_many :probable_family_members, class_name: 'User', foreign_key: :last_name, primary_key: :last_name, dependent: :destroy

  # makes no logical sense to nullify other peoples first names, but using as a test use-case.
  has_many :similarly_named_users, class_name: 'User', foreign_key: :first_name, primary_key: :first_name, dependent: :nullify

  def full_name
    "#{first_name} #{last_name}"
  end
end
