class PartWithDependentPartable < Part
  # can belong to car, or as a sub-part of a part.
  belongs_to :partable, polymorphic: true, dependent: :destroy
end
