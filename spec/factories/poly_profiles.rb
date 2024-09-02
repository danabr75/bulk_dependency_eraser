FactoryBot.define do
  factory :poly_profile do
    bio { Faker::Lorem.sentence }
    profilable { nil }
  end
end