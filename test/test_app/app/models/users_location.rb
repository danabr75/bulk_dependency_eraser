class UsersLocation < ApplicationRecord
  belongs_to :user
  belongs_to :location
end