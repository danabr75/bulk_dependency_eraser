class Address < ApplicationRecord
  belongs_to :user, dependent: :destroy
  has_one :profile, through: :user, dependent: :destroy
end