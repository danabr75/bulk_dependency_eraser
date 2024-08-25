class Part < ApplicationRecord
  # can belong to car, or as a sub-part of a part.
  belongs_to :partable, :polymorphic => true

  has_many :parts, as: :partable, dependent: :destroy
end
