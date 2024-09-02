class NullifyRegistration < ApplicationRecord
  belongs_to :registerable, polymorphic: true
end