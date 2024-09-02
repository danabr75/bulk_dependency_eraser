class Registration < ApplicationRecord
  belongs_to :registerable, polymorphic: true, dependent: :destroy
end