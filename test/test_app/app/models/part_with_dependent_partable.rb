class PartWithDependentPartable < ApplicationRecord
  self.table_name = 'parts'

  # No need to test the dependency tree traversion, tested elsewhere. No need to have vehicle have dependents
  belongs_to :partable, polymorphic: true, dependent: :destroy, class_name: 'VehicleWithNoDependents'
end
