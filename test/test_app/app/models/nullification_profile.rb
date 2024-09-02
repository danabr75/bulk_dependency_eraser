class NullificationProfile < ApplicationRecord
  belongs_to :user, inverse_of: :nullification_profile, optional: true
end