class NullifyPolyProfile < ApplicationRecord
  belongs_to :profilable, polymorphic: true, optional: true
end