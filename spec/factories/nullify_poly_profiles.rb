FactoryBot.define do
  factory :nullify_poly_profile do
    bio { Faker::Lorem.sentence }
    profilable { nil }
  end
end