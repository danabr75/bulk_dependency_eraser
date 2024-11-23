class UserIsFriendsWith < ApplicationRecord
  # No sense for a join to destroy it's joinees, but needed to cover use-case.
  belongs_to :user, dependent: :destroy
  belongs_to :friends_with, class_name: 'User', dependent: :destroy
end