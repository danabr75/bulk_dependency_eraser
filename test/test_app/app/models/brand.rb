class Brand < ApplicationRecord
  has_many :logos
  # Example of an instance scope
  has_many :similarly_named_logos, ->(brand) {
    # find brand_names that contain this brand's name
    where("brand_name LIKE ?", "%#{brand.name}%")
      # exclude logos that are already linked 
      .where.not(brand_id: brand.id)
  }, class_name: "Logo"
end