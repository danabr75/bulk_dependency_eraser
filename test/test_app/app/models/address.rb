class Address < ApplicationRecord
  belongs_to :user, dependent: :destroy, class_name: "UserWithNoDependents"
end