class PolyProfile < ApplicationRecord
  belongs_to :profilable, polymorphic: true
end